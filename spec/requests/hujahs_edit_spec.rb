require "rails_helper"

# HTML/Turbo edit of a hoojah body on a MAIN route (CSRF on). Owner-only + time-boxed
# via HujahPolicy#edit?/#update? (15-min window, closed early by the first conviction).
RSpec.describe "Editing a hoojah body", type: :request do
  let(:owner) { create(:user) }
  let(:hujah) { create(:hujah, user: owner, body: "The original claim about nasi lemak") }

  it "redirects an unauthenticated edit to login" do
    get edit_hujah_path(hujah.slug)
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets the owner open the edit form within the window" do
    sign_in owner
    get edit_hujah_path(hujah.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Edit hoojah")
  end

  it "denies a non-owner opening the edit form" do
    sign_in create(:user)
    get edit_hujah_path(hujah.slug)
    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to eq("Not allowed.")
  end

  it "updates the body for the owner within the window and stamps body_edited_at" do
    sign_in owner
    patch hujah_path(hujah.slug), params: {hujah: {body: "A revised claim about roti canai instead"}}
    expect(response).to have_http_status(:see_other)
    hujah.reload
    expect(hujah.body).to eq("A revised claim about roti canai instead")
    expect(hujah.body_edited_at).to be_present
    expect(response).to redirect_to(hujah_path(hujah.slug))
  end

  it "fails closed on an out-of-window PATCH and leaves the body unchanged" do
    stale = create(:hujah, user: owner, created_at: 16.minutes.ago, body: "A stale claim body here")
    sign_in owner
    patch hujah_path(stale.slug), params: {hujah: {body: "Too late to change this now"}}
    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to eq("Not allowed.")
    expect(stale.reload.body).to eq("A stale claim body here")
  end

  it "fails closed after a conviction has been cast" do
    locked = create(:hujah, user: owner, conviction_count: 1, body: "A locked-in claim body here")
    sign_in owner
    patch hujah_path(locked.slug), params: {hujah: {body: "Trying to edit after lock"}}
    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to eq("Not allowed.")
    expect(locked.reload.body).to eq("A locked-in claim body here")
  end

  it "keeps the old slug resolvable after an edit (FriendlyId history, no new code)" do
    sign_in owner
    old_slug = hujah.slug
    patch hujah_path(hujah.slug), params: {hujah: {body: "A completely different claim now entirely"}}
    expect(hujah.reload.slug).not_to eq(old_slug)
    get "/hoojah/#{old_slug}"
    expect(response).to have_http_status(:ok)
  end

  it "permits allow_debates on a top-level edit" do
    sign_in owner
    patch hujah_path(hujah.slug), params: {hujah: {body: "Revised with debates toggled off now", allow_debates: "0"}}
    expect(hujah.reload.allow_debates).to be(false)
  end

  it "ignores allow_debates on a reply edit (top-level-only param)" do
    parent = create(:hujah)
    reply = create(:hujah, user: owner, parent: parent, body: "A reply body long enough")
    sign_in owner
    patch hujah_path(reply.slug), params: {hujah: {body: "Edited reply body", allow_debates: "0"}}
    expect(reply.reload.body).to eq("Edited reply body")
    expect(reply.allow_debates).to be(true)
  end

  it "restores the persisted slug when a top-level edit fails validation, keeping the form re-submittable" do
    sign_in owner
    original_slug = hujah.slug
    patch hujah_path(hujah.slug), params: {hujah: {body: "short"}} # < 8 chars → invalid for a top-level claim
    expect(response).to have_http_status(:unprocessable_content)
    expect(hujah.reload.slug).to eq(original_slug)
    expect(hujah.body).to eq("The original claim about nasi lemak")
    # the re-rendered form must target the persisted slug, not a phantom one
    expect(response.body).to include(hujah_path(original_slug))
  end
end
