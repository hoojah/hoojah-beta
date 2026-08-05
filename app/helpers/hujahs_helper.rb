module HujahsHelper
  def format_body(text)
    auto_link(simple_format(text), html: {target: "_blank", rel: "noopener"})
  end
end
