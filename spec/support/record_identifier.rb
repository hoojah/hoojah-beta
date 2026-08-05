# The plan's show/vote request specs assert against `dom_id(hujah, :vote_bars)`.
# Request specs (ActionDispatch::IntegrationTest) don't mix in RecordIdentifier by
# default, so make `dom_id` available to them (read-only helper, no side effects).
RSpec.configure do |config|
  config.include ActionView::RecordIdentifier, type: :request
end
