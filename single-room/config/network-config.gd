extends Node
## Centralized network configuration lookup.

const LLM_API_URL_ENV: StringName = &"LLM_API_URL"
const LLM_API_KEY_ENV: StringName = &"LLM_API_KEY"
const LLM_MODEL_ENV: StringName = &"LLM_MODEL"


static func get_llm_api_url() -> String:
	return OS.get_environment(LLM_API_URL_ENV)


static func get_llm_api_key() -> String:
	return OS.get_environment(LLM_API_KEY_ENV)


static func get_llm_model_name() -> String:
	return OS.get_environment(LLM_MODEL_ENV)
