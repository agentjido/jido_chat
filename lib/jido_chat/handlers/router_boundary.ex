defmodule Jido.Chat.Handlers.RouterBoundary do
  @moduledoc false

  # The compiled DSL owns static route declarations. Reify its escaped routes
  # through the upstream constructor so the consumer holds a native opaque Router.
  # These definitions belong to the consuming module, not to this compiler hook.
  @doc false
  defmacro __before_compile__(env) do
    Module.make_overridable(env.module, router: 0, route: 1)
    signal = Macro.var(:signal, nil)
    router_body = quote do: Jido.Signal.Router.new!(routes())
    route_body = quote do: Jido.Signal.Router.route(router(), unquote(signal))
    doc = {:@, [], [{:doc, [], [false]}]}

    {:__block__, [],
     [
       doc,
       {:def, [], [{:router, [], []}, [do: router_body]]},
       doc,
       {:def, [], [{:route, [], [signal]}, [do: route_body]]}
     ]}
  end
end
