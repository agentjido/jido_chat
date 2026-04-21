%Doctor.Config{
  ignore_modules: [
    Jido.Chat.AdapterRegistry,
    Jido.Chat.EventNormalizer,
    Jido.Chat.EventRouter,
    Jido.Chat.HandlerDispatch,
    Jido.Chat.Schema,
    Jido.Chat.Serialization,
    Jido.Chat.WebhookPipeline,
    Jido.Chat.Wire
  ],
  ignore_paths: [],
  min_module_doc_coverage: 40,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 50,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
