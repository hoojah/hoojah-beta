require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  before {
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  }
  after { Rack::Attack.enabled = false }

  it "throttles repeated failed logins from one IP" do
    11.times { post "/login", params: {user: {email: "x@x.com", password: "nope"}} }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles compose (POST /hoojah) per user beyond the limit" do
    user = create(:user)
    sign_in user

    21.times { post "/hoojah", params: {hujah: {body: "spammy take"}} }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles flag (POST /hoojah/:slug/flags) per user beyond the limit" do
    user = create(:user)
    hujah = create(:hujah)
    sign_in user

    16.times { post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "spam"}} }
    expect(response).to have_http_status(:too_many_requests)
  end

  # Slice 9. The throttle counts every request that reaches the rack, so this
  # holds whether the individual extends succeed or 422 — what is pinned is that
  # the path regex matches at all.
  it "throttles extend (POST /debates/:slug/extend) per user beyond the limit" do
    debate = create(:debate, status: :active)
    sign_in debate.challenger

    11.times { post "/debates/#{debate.slug}/extend" }
    expect(response).to have_http_status(:too_many_requests)
  end

  # Rails appends an optional `(.:format)` to EVERY route, and Rack::Request#path
  # returns the raw path with the suffix attached. A matcher anchored on the bare
  # path therefore misses `/…/extend.turbo_stream` — which routes to the very same
  # action — so the request is fully served with no throttle applied. These pin
  # the suffixed form for a representative sample of every matcher shape in the
  # initializer: dynamic-segment paths, and the literal auth paths.
  describe "the optional Rails format suffix must not bypass a throttle" do
    it "throttles extend at .turbo_stream (the format Turbo actually sends)" do
      debate = create(:debate, status: :active)
      sign_in debate.challenger

      11.times { post "/debates/#{debate.slug}/extend.turbo_stream" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles follow at .html — churn here spams new_follower notifications" do
      target = create(:user)
      sign_in create(:user)

      21.times { post "/u/#{target.username}/follow.html" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles unfollow (DELETE) at .html — the other half of the churn loop" do
      target = create(:user)
      sign_in create(:user)

      21.times { delete "/u/#{target.username}/follow.html" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles block at .html" do
      target = create(:user)
      sign_in create(:user)

      21.times { post "/u/#{target.username}/block.html" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles verdicts at .turbo_stream" do
      debate = create(:debate, status: :concluded)
      sign_in create(:user)

      11.times { post "/debates/#{debate.slug}/verdicts.turbo_stream", params: {choice: "challenger"} }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles turns at .turbo_stream" do
      debate = create(:debate, status: :active)
      sign_in debate.challenger

      21.times { post "/debates/#{debate.slug}/turns.turbo_stream", params: {body: "spam"} }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles challenge at .turbo_stream" do
      hujah = create(:hujah)
      argument = create(:hujah, parent: hujah, user: create(:user), vote: 3)
      sign_in create(:user)

      11.times { post "/hoojah/#{hujah.slug}/debates.turbo_stream", params: {argument_id: argument.id, challenger_stance: 1} }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles flags at .turbo_stream" do
      hujah = create(:hujah)
      sign_in create(:user)

      16.times { post "/hoojah/#{hujah.slug}/flags.turbo_stream", params: {flag: {subject: "spam"}} }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles compose at .turbo_stream" do
      sign_in create(:user)

      21.times { post "/hoojah.turbo_stream", params: {hujah: {body: "spammy take"}} }
      expect(response).to have_http_status(:too_many_requests)
    end

    # The auth throttles use string equality on req.path, which has exactly the
    # same hole — and here it gates credential stuffing, not notification churn.
    it "throttles failed logins at .json (credential-stuffing bypass)" do
      11.times { post "/login.json", params: {user: {email: "x@x.com", password: "nope"}} }
      expect(response).to have_http_status(:too_many_requests)
    end

    # .html rather than .json here only because Devise raises UnknownFormat on a
    # JSON password reset — but it raises AFTER sending the reset mail, so the
    # bypass was a live mail-bombing vector either way.
    it "throttles password resets at .html" do
      6.times { post "/password.html", params: {user: {email: "x@x.com"}} }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # SEPARATE defect from the format suffix, and worse: with `devise_for path: ""`,
  # the registration CREATE route is `POST /` — `/signup` is only the GET form.
  # The throttle matched `req.path == "/signup" && req.post?`, which nothing ever
  # sends, so account creation was completely unthrottled.
  it "throttles signup, which POSTs to / (not /signup) under devise path: ''" do
    6.times do |i|
      post "/", params: {user: {username: "spam#{i}", email: "spam#{i}@x.com",
                                password: "password123", password_confirmation: "password123"}}
    end
    expect(response).to have_http_status(:too_many_requests)
  end
end
