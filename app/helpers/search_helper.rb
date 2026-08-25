module SearchHelper
  # Wrap the first case-insensitive occurrence of `query` inside `text` in
  # `text-primary` — the mockup's "#Public**Transp**o**rt**" treatment on a search
  # result row. Injection-safe THE SAME WAY `HujahsHelper#format_body` is: `text` is
  # arbitrary user content (a hoojah body, a hashtag's display casing, a full name),
  # so escaping happens on each of the three raw-text FRAGMENTS (before/match/after)
  # individually, never via a gsub over already-rendered HTML.
  #
  # Only the first occurrence is marked — matches the mockup, and stops a short query
  # from wrapping every repeat of itself inside a long hoojah body.
  #
  # A blank query, or no match at all, returns the plain escaped text: no `<span>` is
  # emitted, so nothing here can introduce a tag into text a caller depends on staying
  # literal when there is nothing to highlight (see `search/_result_user`'s comment on
  # why the @handle stays out of this entirely).
  def highlight_match(text, query)
    text = text.to_s
    query = query.to_s.strip
    return ERB::Util.html_escape(text) if query.blank?

    index = text.downcase.index(query.downcase)
    return ERB::Util.html_escape(text) unless index

    before = text[0...index]
    match = text[index, query.length]
    after = text[(index + query.length)..] || ""

    safe_join([ERB::Util.html_escape(before), content_tag(:span, match, class: "text-primary"), ERB::Util.html_escape(after)])
  end
end
