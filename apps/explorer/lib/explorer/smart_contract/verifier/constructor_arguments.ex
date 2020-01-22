defmodule Explorer.SmartContract.Verifier.ConstructorArguments do
  @moduledoc """
  Smart contract contrstructor arguments verification logic.
  """
  alias ABI.{FunctionSelector, TypeDecoder}
  alias Explorer.Chain

  def verify(address_hash, contract_code, arguments_data) do
    arguments_data = arguments_data |> String.trim_trailing() |> String.trim_leading("0x")

    creation_code =
      address_hash
      |> Chain.contract_creation_input_data()
      |> String.replace("0x", "")

    check_func = fn assumed_arguments -> assumed_arguments == arguments_data end

    if verify_older_version(creation_code, contract_code, check_func) do
      true
    else
      extract_constructor_arguments(creation_code, check_func)
    end
  end

  # Earlier versions of Solidity didn't have whisper code.
  # constructor argument were directly appended to source code
  defp verify_older_version(creation_code, contract_code, check_func) do
    creation_code
    |> String.split(contract_code)
    |> List.last()
    |> check_func.()
  end

  defp extract_constructor_arguments(code, check_func) do
    case code do
      # Solidity ~ 4.23 # https://solidity.readthedocs.io/en/v0.4.23/metadata.html
      "a165627a7a72305820" <> <<_::binary-size(64)>> <> "0029" <> constructor_arguments ->
        extract_constructor_arguments_check_func(constructor_arguments, check_func)

      # Solidity >= 0.5.10 https://solidity.readthedocs.io/en/v0.5.10/metadata.html
      "a265627a7a72305820" <>
          <<_::binary-size(64)>> <> "64736f6c6343" <> <<_::binary-size(6)>> <> "0032" <> constructor_arguments ->
        extract_constructor_arguments_check_func(constructor_arguments, check_func)

      # Solidity >= 0.5.11 https://github.com/ethereum/solidity/blob/develop/Changelog.md#0511-2019-08-12
      # Metadata: Update the swarm hash to the current specification, changes bzzr0 to bzzr1 and urls to use bzz-raw://
      "a265627a7a72315820" <>
          <<_::binary-size(64)>> <> "64736f6c6343" <> <<_::binary-size(6)>> <> "0032" <> constructor_arguments ->
        extract_constructor_arguments_check_func(constructor_arguments, check_func)

      # Solidity >= 0.6.0 https://github.com/ethereum/solidity/blob/develop/Changelog.md#060-2019-12-17
      # https://github.com/ethereum/solidity/blob/26b700771e9cc9c956f0503a05de69a1be427963/docs/metadata.rst#encoding-of-the-metadata-hash-in-the-bytecode
      # IPFS is used instead of Swarm
      # The current version of the Solidity compiler usually adds the following to the end of the deployed bytecode:
      # 0xa2
      # 0x64 'i' 'p' 'f' 's' 0x58 0x22 <34 bytes IPFS hash>
      # 0x64 's' 'o' 'l' 'c' 0x43 <3 byte version encoding>
      # 0x00 0x32
      # Note: there is a bug in the docs. Instead of 0x32, 0x33 should be used.
      # Fixing PR has been created https://github.com/ethereum/solidity/pull/8174
      "a264697066735822" <>
          <<_::binary-size(68)>> <> "64736f6c6343" <> <<_::binary-size(6)>> <> "0033" <> constructor_arguments ->
        extract_constructor_arguments_check_func(constructor_arguments, check_func)

      <<>> ->
        check_func.("")

      <<_::binary-size(2)>> <> rest ->
        extract_constructor_arguments(rest, check_func)
    end
  end

  defp extract_constructor_arguments_check_func(constructor_arguments, check_func) do
    check_func_result = check_func.(constructor_arguments)

    if check_func_result do
      check_func_result
    else
      extract_constructor_arguments(constructor_arguments, check_func)
    end
  end

  def find_constructor_arguments(address_hash, abi) do
    creation_code =
      address_hash
      |> Chain.contract_creation_input_data()
      |> String.replace("0x", "")

    constructor_abi = Enum.find(abi, fn el -> el["type"] == "constructor" && el["inputs"] != [] end)

    input_types = Enum.map(constructor_abi["inputs"], &FunctionSelector.parse_specification_type/1)

    check_func = fn assumed_arguments ->
      try do
        _ =
          assumed_arguments
          |> Base.decode16!(case: :mixed)
          |> TypeDecoder.decode_raw(input_types)

        assumed_arguments
      rescue
        _ -> false
      end
    end

    extract_constructor_arguments(creation_code, check_func)
  end

  def extract_require_messages_from_constructor(contract_source_code) do
    constructor = find_constructor_content(contract_source_code)
    require_contents = find_require_in_constructor(constructor)

    messages_list =
      Enum.reduce(require_contents, [], fn require_content, msgs ->
        msg = get_require_message_hex(require_content)
        if msg, do: msgs ++ [msg]
      end)

    if messages_list, do: messages_list, else: []
  end

  def find_constructor_content(contract_source_code) do
    case String.split(contract_source_code, "constructor", parts: 2) do
      [_, right_from_contstructor] ->
        case String.split(right_from_contstructor, "{", parts: 2) do
          [_, right_from_contstructor_inside] ->
            case String.split(right_from_contstructor_inside, "}", parts: 2) do
              [constructor, _] ->
                constructor

              [_] ->
                nil
            end

          [_] ->
            nil
        end

      [_] ->
        nil
    end
  end

  def find_require_in_constructor(constructor) do
    if constructor do
      [_ | requires] = String.split(constructor, "require")

      Enum.reduce(requires, [], fn right_from_require, requires_list ->
        [_ | [right_from_require_inside]] = String.split(right_from_require, "(", parts: 2)
        [require_content | _] = String.split(right_from_require_inside, ");", parts: 2)
        requires_list ++ [require_content]
      end)
    else
      []
    end
  end

  def get_require_message_hex(require_content) do
    case String.split(require_content, ",", parts: 2) do
      [_ | [msg]] ->
        String.trim(msg)
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")
        |> String.trim_leading("'")
        |> String.trim_trailing("'")
        |> Base.encode16(case: :lower)

      [_] ->
        nil
    end
  end
end
