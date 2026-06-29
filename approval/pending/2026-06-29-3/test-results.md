.............................................FF......................... [ 69%]
......F.......F................                                          [100%]
=================================== FAILURES ===================================
_________ TestProviderContractsUnchanged.test_memory_provider_contract _________
agent-env-selfhosted/tests/test_context_budget.py:182: in test_memory_provider_contract
    assert set(vars(artifact)) == {"source", "content"}
E   AssertionError: assert {'content', '...ty', 'source'} == {'content', 'source'}
E     
E     Extra items in the left set:
E     'loaded'
E     'priority'
E     'estimated_tokens'
E     'metadata'
E     Use -v to get more diff
_________ TestProviderContractsUnchanged.test_vault_provider_contract __________
agent-env-selfhosted/tests/test_context_budget.py:199: in test_vault_provider_contract
    assert set(vars(artifact)) == {"source", "content"}
E   AssertionError: assert {'content', '...ty', 'source'} == {'content', 'source'}
E     
E     Extra items in the left set:
E     'loaded'
E     'priority'
E     'estimated_tokens'
E     'metadata'
E     Use -v to get more diff
___________________ test_memory_provider_contract_unchanged ____________________
agent-env-selfhosted/tests/test_memory_provider.py:67: in test_memory_provider_contract_unchanged
    assert set(vars(artifact)) == {"source", "content"}
E   AssertionError: assert {'content', '...ty', 'source'} == {'content', 'source'}
E     
E     Extra items in the left set:
E     'loaded'
E     'priority'
E     'estimated_tokens'
E     'metadata'
E     Use -v to get more diff
________ TestSuccessfulRetrieval.test_vault_provider_contract_unchanged ________
agent-env-selfhosted/tests/test_vault_provider.py:217: in test_vault_provider_contract_unchanged
    assert set(vars(artifact)) == {"source", "content"}
E   AssertionError: assert {'content', '...ty', 'source'} == {'content', 'source'}
E     
E     Extra items in the left set:
E     'loaded'
E     'priority'
E     'estimated_tokens'
E     'metadata'
E     Use -v to get more diff
=========================== short test summary info ============================
FAILED agent-env-selfhosted/tests/test_context_budget.py::TestProviderContractsUnchanged::test_memory_provider_contract
FAILED agent-env-selfhosted/tests/test_context_budget.py::TestProviderContractsUnchanged::test_vault_provider_contract
FAILED agent-env-selfhosted/tests/test_memory_provider.py::test_memory_provider_contract_unchanged
FAILED agent-env-selfhosted/tests/test_vault_provider.py::TestSuccessfulRetrieval::test_vault_provider_contract_unchanged
4 failed, 99 passed in 0.24s
