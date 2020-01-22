defmodule Explorer.SmartContract.Verifier.ConstructorArgumentsTest do
  use Explorer.DataCase

  import Explorer.Factory

  alias Explorer.Chain.Data
  alias Explorer.SmartContract.Verifier.ConstructorArguments

  describe "verify/3" do
    test "veriies constructor constructor arguments with whisper data" do
      constructor_arguments = Base.encode16(:crypto.strong_rand_bytes(64), case: :lower)
      address = insert(:address)

      input =
        "a165627a7a72305820" <>
          Base.encode16(:crypto.strong_rand_bytes(32), case: :lower) <> "0029" <> constructor_arguments

      input_data = %Data{
        bytes: Base.decode16!(input, case: :lower)
      }

      :transaction
      |> insert(created_contract_address_hash: address.hash, input: input_data)
      |> with_block()

      assert ConstructorArguments.verify(address.hash, "", constructor_arguments)
    end

    test "verifies with multiple nested constructor arguments" do
      address = insert(:address)

      constructor_arguments =
        "000000000000000000000000314159265dd8dbb310642f98f50c066173c1259b93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae00000000000000000000000000000000000000000000000000000000590b09b0"

      input =
        "a165627a7a72305820fbfa6f8a2024760ef0e0eb29a332c9a820526e92f8b4fbcce6f00c7643234b1400297b6c4b278d165a6b33958f8ea5dfb00c8c9d4d0acf1985bef5d10786898bc3e7a165627a7a723058203c2db82e7c80cd1e371fe349b03d49b812c324ba4a3fcd063b7bc2662353c5de0029000000000000000000000000314159265dd8dbb310642f98f50c066173c1259b93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae00000000000000000000000000000000000000000000000000000000590b09b0"

      input_data = %Data{
        bytes: Base.decode16!(input, case: :lower)
      }

      :transaction
      |> insert(created_contract_address_hash: address.hash, input: input_data)
      |> with_block()

      assert ConstructorArguments.verify(address.hash, "", constructor_arguments)
    end

    test "verifies older version of Solidity where constructor_arguments were directly appended to source code" do
      address = insert(:address)

      constructor_arguments =
        "000000000000000000000000314159265dd8dbb310642f98f50c066173c1259b93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae00000000000000000000000000000000000000000000000000000000590b09b0"

      source_code = "0001"

      input = source_code <> constructor_arguments

      input_data = %Data{
        bytes: Base.decode16!(input, case: :lower)
      }

      :transaction
      |> insert(created_contract_address_hash: address.hash, input: input_data)
      |> with_block()

      assert ConstructorArguments.verify(address.hash, source_code, constructor_arguments)
    end

    test "get require messages from constructor" do
      contract_source_code = """
      pragma solidity 0.6.1;


      contract HomeBridge {
          uint public validatorsRequiredPercent;

          constructor(address _proxy, uint256 _validatorsRequiredPercent) public {
              require       (
                  address(_proxy) != address(0),



                  "proxy must not be the zero address!"
              );


              require(
                  _validatorsRequiredPercent >= 0 &&
                      _validatorsRequiredPercent <= 100,
                  "_validatorsRequiredPercent must be between 0 and 100"
              );
              validatorsRequiredPercent = _validatorsRequiredPercent;
          }
      }
      """

      result = ConstructorArguments.extract_require_messages_from_constructor(contract_source_code)

      assert result == [
               "70726f7879206d757374206e6f7420626520746865207a65726f206164647265737321",
               "5f76616c696461746f7273526571756972656450657263656e74206d757374206265206265747765656e203020616e6420313030"
             ]
    end

    test "get require messages with a single quote from constructor" do
      contract_source_code = """
      pragma solidity 0.6.1;


      contract HomeBridge {
          uint public validatorsRequiredPercent;

          constructor(address _proxy, uint256 _validatorsRequiredPercent) public {


              require(
                  _validatorsRequiredPercent >= 0 &&
                      _validatorsRequiredPercent <= 100,
                  '_validatorsRequiredPercent must be between 0 and 100'
              );
              validatorsRequiredPercent = _validatorsRequiredPercent;
          }
      }
      """

      result = ConstructorArguments.extract_require_messages_from_constructor(contract_source_code)

      assert result == [
               "5f76616c696461746f7273526571756972656450657263656e74206d757374206265206265747765656e203020616e6420313030"
             ]
    end

    test "get require messages with different quotes inside from constructor" do
      contract_source_code = """
      pragma solidity 0.6.1;


      contract HomeBridge {
          uint public validatorsRequiredPercent;

          constructor(uint256 _validatorsRequiredPercent) public {


              require(
                  _validatorsRequiredPercent >= 0 &&
                      _validatorsRequiredPercent <= 100,
                  "_val\"idatorsReq'uiredPercent must be ' between \" 0 and 100"
              );
              validatorsRequiredPercent = _validatorsRequiredPercent;
          }
      }
      """

      result = ConstructorArguments.extract_require_messages_from_constructor(contract_source_code)

      assert result == [
               "5f76616c22696461746f727352657127756972656450657263656e74206d7573742062652027206265747765656e2022203020616e6420313030"
             ]
    end

    test "get empty require messages from constructor with require without message" do
      contract_source_code = """
      pragma solidity 0.6.1;


      contract HomeBridge {
          uint public validatorsRequiredPercent;

          constructor(uint256 _validatorsRequiredPercent) public {


              require(
                  _validatorsRequiredPercent >= 0 &&
                      _validatorsRequiredPercent <= 100
              );
              validatorsRequiredPercent = _validatorsRequiredPercent;
          }
      }
      """

      result = ConstructorArguments.extract_require_messages_from_constructor(contract_source_code)

      assert result == []
    end

    test "get empty require messages from constructor" do
      contract_source_code = """
      pragma solidity 0.6.1;


      contract HomeBridge {
          uint public validatorsRequiredPercent;

          constructor(address _proxy, uint256 _validatorsRequiredPercent) public {
              validatorsRequiredPercent = _validatorsRequiredPercent;
          }
      }
      """

      result = ConstructorArguments.extract_require_messages_from_constructor(contract_source_code)

      assert result == []
    end
  end

  test "get empty require messages if no constructor" do
    contract_source_code = """
    pragma solidity 0.6.1;


    contract HomeBridge {
        uint public validatorsRequiredPercent;

    }
    """

    result = ConstructorArguments.extract_require_messages_from_constructor(contract_source_code)

    assert result == []
  end
end
