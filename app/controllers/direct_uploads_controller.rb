# Slice 2 (image attachments): the composer direct-uploads through this authenticated
# subclass instead of the stock ActiveStorage::DirectUploadsController, which ships with no
# authentication and no throttle. This slice makes direct upload a live path for the first
# time, so at minimum require a signed-in user — otherwise an anonymous client can mint
# unlimited orphan blobs of any size straight at storage.
#
# DEFERRED (docs/superpowers/SECURITY-FINDINGS.md): a Rack::Attack throttle and a per-blob
# byte cap enforced at upload time still do not exist for this route. The composer's 5 MB
# check is client-side only and is not a server control.
class DirectUploadsController < ActiveStorage::DirectUploadsController
  before_action :authenticate_user!
end
