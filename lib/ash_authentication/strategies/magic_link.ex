defmodule AshAuthentication.Strategy.MagicLink do
  alias __MODULE__.{Dsl, Transformer, Verifier}

  @moduledoc """
  Strategy for authentication using a magic link.

  In order to use magic link authentication your resource needs to meet the
  following minimum requirements:

  1. Have a primary key.
  2. A uniquely constrained identity field (eg `username` or `email`)
  3. Have tokens enabled.

  There are other options documented in the DSL.

  ### Example

  ```elixir
  defmodule MyApp.Accounts.User do
    use Ash.Resource,
      extensions: [AshAuthentication],
      domain: MyApp.Accounts

    attributes do
      uuid_primary_key :id
      attribute :email, :ci_string, allow_nil?: false
    end

    authentication do
      strategies do
        magic_link do
          identity_field :email
          sender fn user_or_email, token, _opts ->
            # will be a user if the token relates to an existing user
            # will be an email if there is no matching user (such as during sign up)
            # opts will contain the `tenant` key, use this if you need to alter the link based
            # on the tenant that requested the token
            MyApp.Emails.deliver_magic_link(user_or_email, token)
          end
        end
      end
    end

    identities do
      identity :unique_email, [:email]
    end
  end
  ```

  ## Tenancy

  Note that the tenant is provided to the sender in the `opts` key. Use this if you need
  to modify the url (i.e `tenant.app.com`) based on the tenant that requested the token.

  ## Actions

  By default the magic link strategy will automatically generate the request and
  sign-in actions for you, however you're free to define them yourself.  If you
  do, then the action will be validated to ensure that all the needed
  configuration is present.

  If you wish to work with the actions directly from your code you can do so via
  the `AshAuthentication.Strategy` protocol.

  ### Examples

  Requesting that a magic link token is sent for a user:

      iex> strategy = Info.strategy!(Example.User, :magic_link)
      ...> user = build_user()
      ...> Strategy.action(strategy, :request, %{"username" => user.username})
      :ok

  Signing in using a magic link token:

      ...> {:ok, token} = MagicLink.request_token_for(strategy, user)
      ...> {:ok, signed_in_user} = Strategy.action(strategy, :sign_in, %{"token" => token})
      ...> signed_in_user.id == user
      true

  ## Plugs

  The magic link strategy provides plug endpoints for both request and sign-in
  actions.

  If you wish to work with the plugs directly, you can do so via the
  `AshAuthentication.Strategy` protocol.

  ### Examples:

  Dispatching to plugs directly:

      iex> strategy = Info.strategy!(Example.User, :magic_link)
      ...> user = build_user()
      ...> conn = conn(:post, "/user/magic_link/request", %{"user" => %{"username" => user.username}})
      ...> conn = Strategy.plug(strategy, :request, conn)
      ...> {_conn, {:ok, nil}} = Plug.Helpers.get_authentication_result(conn)

      ...> {:ok, token} = MagicLink.request_token_for(strategy, user)
      ...> conn = conn(:get, "/user/magic_link", %{"token" => token})
      ...> conn = Strategy.plug(strategy, :sign_in, conn)
      ...> {_conn, {:ok, signed_in_user}} = Plug.Helpers.get_authentication_result(conn)
      ...> signed_in_user.id == user.id
      true

  See the [Magic Link Tutorial](/documentation/tutorial/magic-links.md) for more information.
  """

  defstruct identity_field: :username,
            name: nil,
            request_action_name: nil,
            resource: nil,
            sender: nil,
            prevent_hijacking?: true,
            registration_enabled?: false,
            sign_in_action_name: nil,
            lookup_action_name: nil,
            single_use_token?: true,
            strategy_module: __MODULE__,
            token_lifetime: {10, :minutes},
            token_param_name: :token

  use AshAuthentication.Strategy.Custom, entity: Dsl.dsl()

  alias Ash.Resource
  alias AshAuthentication.Jwt

  @type t :: %__MODULE__{
          identity_field: atom,
          name: atom,
          prevent_hijacking?: boolean,
          registration_enabled?: boolean,
          request_action_name: atom,
          resource: module,
          sender: {module, keyword},
          lookup_action_name: nil,
          single_use_token?: boolean,
          sign_in_action_name: atom,
          strategy_module: module,
          token_lifetime: pos_integer(),
          token_param_name: atom
        }

  defdelegate transform(strategy, dsl_state), to: Transformer
  defdelegate verify(strategy, dsl_state), to: Verifier

  @doc """
  Generate a magic link token for a user.

  Used by `AshAuthentication.Strategy.MagicLink.RequestPreparation`.
  """
  @spec request_token_for(t, Resource.record(), opts :: Keyword.t(), context :: map()) ::
          {:ok, binary} | :error
  def request_token_for(strategy, user, opts \\ [], context \\ %{})
      when is_struct(strategy, __MODULE__) and is_struct(user, strategy.resource) do
    case Jwt.token_for_user(
           user,
           %{
             "act" => strategy.sign_in_action_name,
             "identity" => Map.get(user, strategy.identity_field)
           },
           Keyword.merge(opts,
             token_lifetime: strategy.token_lifetime,
             purpose: :magic_link
           ),
           context
         ) do
      {:ok, token, _claims} -> {:ok, token}
      :error -> :error
    end
  end

  @doc """
  Generate a magic link token for an identity field.

  Used by `AshAuthentication.Strategy.MagicLink.RequestPreparation`.
  """
  def request_token_for_identity(strategy, identity, context)
      when is_struct(strategy, __MODULE__) do
    case Jwt.token_for_resource(
           strategy.resource,
           %{
             "act" => strategy.sign_in_action_name,
             "identity" => to_string(identity)
           },
           [token_lifetime: strategy.token_lifetime, purpose: :magic_link],
           context
         ) do
      {:ok, token, _claims} -> {:ok, token}
      :error -> :error
    end
  end
end
