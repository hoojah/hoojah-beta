require "rails_helper"

# HTML/Turbo twin of the Api::V1 destroy (spec/requests/api/v1/hujahs_spec.rb). A
# WRITE on a MAIN route (CSRF on); owner-only via HujahPolicy#destroy?, and refused
# when the hoojah carries replies or a debate (other people's content that
# `dependent: :destroy` would cascade away).
RSpec.describe "DELETE /hoojah/:slug", type: :request do
  let(:owner) { create(:user) }
  let(:hujah) { create(:hujah, user: owner) }

  it "redirects an unauthenticated delete to login and keeps the hoojah" do
    delete hujah_path(hujah.slug)

    expect(response).to redirect_to(new_user_session_path)
    expect(Hujah.exists?(hujah.id)).to be(true)
  end

  it "denies a non-owner (Pundit) and keeps the hoojah" do
    sign_in create(:user)

    delete hujah_path(hujah.slug)

    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to eq("Not allowed.")
    expect(Hujah.exists?(hujah.id)).to be(true)
  end

  it "refuses to delete a hoojah that has a response and keeps it" do
    child = create(:hujah)
    child.update!(parent_id: hujah.id)
    sign_in owner

    delete hujah_path(hujah.slug)

    expect(response).to redirect_to(hujah_path(hujah.slug))
    expect(flash[:alert]).to eq("You can't delete a hoojah that has responses or a debate.")
    expect(Hujah.exists?(hujah.id)).to be(true)
  end

  it "refuses to delete a hoojah that has a debate and keeps it" do
    create(:debate, hujah: hujah)
    sign_in owner

    delete hujah_path(hujah.slug)

    expect(response).to redirect_to(hujah_path(hujah.slug))
    expect(flash[:alert]).to eq("You can't delete a hoojah that has responses or a debate.")
    expect(Hujah.exists?(hujah.id)).to be(true)
  end

  it "refuses to let the owner delete their own moderator-removed hoojah" do
    # HujahPolicy#destroy? gates on moderation_status: a removed hoojah is staff-only and
    # its body is moderation evidence, so the author must not be able to hard-delete it
    # (via a replayed/direct DELETE — the UI never shows the button on a removed hoojah).
    hujah.update!(moderation_status: :removed)
    sign_in owner

    delete hujah_path(hujah.slug)

    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to eq("Not allowed.")
    expect(Hujah.exists?(hujah.id)).to be(true)
  end

  it "lets the owner delete a clean hoojah and redirects to the feed" do
    id = hujah.id
    sign_in owner

    delete hujah_path(hujah.slug)

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Hoojah deleted.")
    expect(Hujah.exists?(id)).to be(false)
  end

  it "answers a Turbo Stream delete with a visit action back to the feed" do
    id = hujah.id
    sign_in owner

    delete hujah_path(hujah.slug), as: :turbo_stream

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('action="visit"')
    expect(response.body).to include('url="/"')
    expect(Hujah.exists?(id)).to be(false)
  end

  # Issue #38: after a successful delete, return the user to the page they were on
  # BEFORE they opened this hoojah — threaded through as a `return_to` param and
  # RE-VALIDATED server-side (never trust the param blindly).
  describe "return_to (issue #38)" do
    it "redirects to a valid same-origin return_to path" do
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "/u/someusername"}

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/u/someusername")
    end

    it "carries the return_to destination into the Turbo Stream visit action" do
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "/u/someusername"}, as: :turbo_stream

      expect(response.body).to include('action="visit"')
      expect(response.body).to include('url="/u/someusername"')
    end

    it "falls back to the feed when no return_to is given" do
      sign_in owner

      delete hujah_path(hujah.slug)

      expect(response).to redirect_to(root_path)
    end

    it "ignores an absolute off-site return_to (open-redirect guard) and falls back to the feed" do
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "https://evil.com"}

      expect(response).to redirect_to(root_path)
    end

    it "ignores a protocol-relative off-site return_to and falls back to the feed" do
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "//evil.com"}

      expect(response).to redirect_to(root_path)
    end

    it "ignores an opaque javascript: return_to (no crash) and falls back to the feed" do
      id = hujah.id
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "javascript:alert(1)"}

      expect(response).to redirect_to(root_path)
      expect(Hujah.exists?(id)).to be(false)
    end

    it "ignores an opaque mailto: return_to and falls back to the feed" do
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "mailto:x@y.com"}

      expect(response).to redirect_to(root_path)
    end

    it "ignores a backslash-prefixed return_to and falls back to the feed" do
      sign_in owner

      delete hujah_path(hujah.slug), params: {return_to: "/\\evil.com"}

      expect(response).to redirect_to(root_path)
    end

    it "ignores a return_to pointing at the deleted hoojah itself (it's about to 404)" do
      sign_in owner
      own_path = hujah_path(hujah.slug)

      delete hujah_path(hujah.slug), params: {return_to: own_path}

      expect(response).to redirect_to(root_path)
    end
  end
end
