require "rails_helper"

RSpec.describe "Hujah slugs (friendly_id)", type: :model do
  let(:user) { create(:user) }

  it "generates unique, length-bounded slugs from the body" do
    a = Hujah.create!(user: user, body: "Nasi lemak is the best breakfast in Malaysia hands down")
    b = Hujah.create!(user: user, body: "Nasi lemak is the best breakfast in Malaysia hands down")
    expect(a.slug).not_to eq(b.slug)          # collision-safe
    expect(a.slug.length).to be <= 80
    expect(Hujah.friendly.find(a.slug)).to eq(a)
  end

  it "keeps old slugs resolvable after a body edit (history)" do
    h = Hujah.create!(user: user, body: "Original take on teh tarik")
    old = h.slug
    h.update!(body: "Revised take on teh tarik entirely")
    expect(Hujah.friendly.find(old)).to eq(h)
  end
end
