module HujahsHelper
  # Render a hoojah body: linkify URLs, preserve paragraphs, and turn @handles
  # into profile links -- WITHOUT ever gsub-ing over already-rendered HTML.
  #
  # CRITICAL (security): mentions are tokenized on the RAW text BEFORE
  # simple_format/auto_link, then the anchor is substituted AFTER, keyed on the
  # U+E000 / U+E001 private-use markers our tokenizer inserts. gsub-ing @handles
  # over rendered HTML would match an "@" inside an auto_link'd href="mailto:..."
  # / URL and splice an unescaped quote, corrupting the markup. Because the
  # restoration regex requires OUR markers, an "@" in an email/URL is never
  # touched, and the handle is ERB::Util-escaped on output.
  #
  # Deviation from spec section 6 (documented): the token embeds the literal
  # @handle (not an array index), and a trailing .delete strips markers that
  # rails_autolink 1.1.8 splits off a URL -- its trailing-punctuation trimmer
  # (href.sub!(/[^\p{Word}\/\-=;]$/, "")) moves the non-word U+E001 marker
  # outside the <a>. Net effect: a mention that lands inside a URL (e.g.
  # https://medium.com/@who) is no longer marker-contiguous after auto_link, so it
  # is left as literal text (URL intact) instead of becoming a profile link -- the
  # behaviour the spec's own test asserts.
  MENTION_OPEN = [0xE000].pack("U")   # U+E000, private-use (can't appear in user text)
  MENTION_CLOSE = [0xE001].pack("U")  # U+E001, private-use
  MENTION_TOKEN_RE = /#{MENTION_OPEN}@([a-zA-Z0-9_]+)#{MENTION_CLOSE}/

  # #hashtags reuse the mention tokenizer's design with a DISTINCT private-use marker
  # pair (U+E002 / U+E003), for the identical security reason: tags are tokenized on
  # the RAW text BEFORE auto_link, then linkified AFTER via these markers, so a `#`
  # that auto_link folds into a URL fragment (e.g. https://x.com/page#frag) is never
  # marker-wrapped and therefore never becomes a tag link. `Hujah::HASHTAG_RE` is the
  # single source of truth for what counts as a tag (shared with sync_hashtags).
  HASHTAG_OPEN = [0xE002].pack("U")   # U+E002, private-use
  HASHTAG_CLOSE = [0xE003].pack("U")  # U+E003, private-use
  HASHTAG_TOKEN_RE = /#{HASHTAG_OPEN}#(\p{L}[\p{L}0-9_]*)#{HASHTAG_CLOSE}/

  # Issue #11: inline emphasis (**bold** / *italic* / _underline_) reuses the SAME
  # tokens-before-render technique for the SAME security reason: the markdown spans are
  # tokenized on the RAW text BEFORE simple_format/auto_link with three more DISTINCT
  # private-use marker pairs (U+E004..U+E009), and the real <strong>/<em>/<u> tags are
  # substituted AFTER. No gsub ever runs over rendered HTML, so the sanitizer allowlist
  # is NOT widened and no new XSS surface is introduced. The content between a marker
  # pair has already been HTML-escaped by simple_format by substitution time, and may
  # legitimately contain the mention/hashtag anchors spliced in just above (that's fine
  # — the anchors are our own trusted markup, not user text).
  #
  # The boundary lookbehind/lookahead is load-bearing: a preceding word char fails the
  # `(?<=\A|\s|\()` lookbehind, so a `_` inside a URL (…/wiki/Foo_bar_baz) or an
  # `@user_name` handle never opens an underline span; `[^*\n]`/`[^_\n]` keep a span
  # single-line so it can't straddle a simple_format `<p>` boundary. And, exactly as with
  # the U+E001 mention marker, the final `.delete` strips any orphaned emphasis marker
  # that auto_link's trailing-punctuation trimmer may have relocated outside an <a>, so a
  # stranded marker degrades to silent removal (span unformatted, URL intact) rather than
  # leaking a private-use codepoint.
  STRONG_OPEN = [0xE004].pack("U")     # U+E004, private-use
  STRONG_CLOSE = [0xE005].pack("U")    # U+E005, private-use
  EM_OPEN = [0xE006].pack("U")         # U+E006, private-use
  EM_CLOSE = [0xE007].pack("U")        # U+E007, private-use
  UNDERLINE_OPEN = [0xE008].pack("U")  # U+E008, private-use
  UNDERLINE_CLOSE = [0xE009].pack("U") # U+E009, private-use

  # Tokenizer regexes, applied to RAW text in order bold → italic → underline (bold must
  # precede italic so `**x**` is consumed as one bold span, never two italic asterisks).
  BOLD_RE = /(?<=\A|\s|\()\*\*([^*\n]+)\*\*(?=\z|\s|[[:punct:]])/
  ITALIC_RE = /(?<=\A|\s|\()\*([^*\n]+)\*(?=\z|\s|[[:punct:]])/
  UNDERLINE_RE = /(?<=\A|\s|\()_([^_\n]+)_(?=\z|\s|[[:punct:]])/

  # Restore regexes, non-greedy so adjacent spans (`**a** **b**`) don't fuse; the span
  # content is already escaped and may carry our own mention/hashtag anchors.
  STRONG_TOKEN_RE = /#{STRONG_OPEN}(.+?)#{STRONG_CLOSE}/
  EM_TOKEN_RE = /#{EM_OPEN}(.+?)#{EM_CLOSE}/
  UNDERLINE_TOKEN_RE = /#{UNDERLINE_OPEN}(.+?)#{UNDERLINE_CLOSE}/

  def format_body(text)
    tokenized = text.to_s
      .gsub(Hujah::MENTION_RE) { "#{MENTION_OPEN}@#{$1}#{MENTION_CLOSE}" }
      .gsub(Hujah::HASHTAG_RE) { "#{HASHTAG_OPEN}##{$1}#{HASHTAG_CLOSE}" }
      .gsub(BOLD_RE) { "#{STRONG_OPEN}#{$1}#{STRONG_CLOSE}" }
      .gsub(ITALIC_RE) { "#{EM_OPEN}#{$1}#{EM_CLOSE}" }
      .gsub(UNDERLINE_RE) { "#{UNDERLINE_OPEN}#{$1}#{UNDERLINE_CLOSE}" }
    linked = auto_link(simple_format(tokenized), html: {target: "_blank", rel: "noopener"})
    linked
      .gsub(MENTION_TOKEN_RE) do
        handle = $1
        %(<a href="/u/#{ERB::Util.url_encode(handle)}" class="text-primary">@#{ERB::Util.html_escape(handle)}</a>)
      end
      .gsub(HASHTAG_TOKEN_RE) do
        name = $1
        # `.downcase` on the href matches Hashtag.canonical (and the /t/:name route).
        %(<a href="/t/#{ERB::Util.url_encode(name.downcase)}" class="text-primary">##{ERB::Util.html_escape(name)}</a>)
      end
      # Emphasis restored AFTER the mention/hashtag anchors, so a span wrapping a mention
      # (`**hi @rudz**`) sees the finished <a> as its content, not a leftover token.
      .gsub(STRONG_TOKEN_RE) { "<strong>#{$1}</strong>" }
      .gsub(EM_TOKEN_RE) { "<em>#{$1}</em>" }
      .gsub(UNDERLINE_TOKEN_RE) { "<u>#{$1}</u>" }
      .delete(MENTION_OPEN + MENTION_CLOSE + HASHTAG_OPEN + HASHTAG_CLOSE +
        STRONG_OPEN + STRONG_CLOSE + EM_OPEN + EM_CLOSE + UNDERLINE_OPEN + UNDERLINE_CLOSE)
      .html_safe
  end

  # Issue #38: after deleting a hoojah the user should land back on the page they
  # were on BEFORE opening this hoojah's show page — captured at button-render time
  # from `request.referer` (at DESTROY time the referer is the show page itself, so
  # capturing it then would be useless) and threaded through as a `return_to` param.
  #
  # This validates a candidate destination on BOTH sides (render AND destroy — the
  # controller re-validates, never trusting the param blindly) and returns a SAFE
  # internal path, or nil for the caller to fall back to root_path:
  #   - `raw` may be an absolute same-origin URL (that's what `request.referer` is)
  #     OR an already-extracted local path (that's what the round-tripped param is);
  #   - a cross-origin absolute URL, a protocol-relative "//host", or anything that
  #     doesn't resolve to a leading-single-slash local path is rejected
  #     (open-redirect guard);
  #   - the deleted hoojah's OWN show path is rejected too — it's about to 404.
  # We keep only the path (+ query), so the returned value is always a local path.
  def safe_return_path(raw, current_hujah_path)
    raw = raw.to_s.strip
    return nil if raw.empty?
    # Protocol-relative ("//host") slips past a naive leading-slash check, so reject
    # it before anything else.
    return nil if raw.start_with?("//")

    uri = begin
      URI.parse(raw)
    rescue URI::InvalidURIError
      return nil
    end

    # Opaque-scheme URIs (`javascript:alert(1)`, `mailto:x@y`, `tel:`, `data:`,
    # `https:evil.com`) have a scheme and an opaque body but NO host and a nil path,
    # so they must be rejected here — otherwise the nil path would crash the guard
    # below, and since the controller deletes BEFORE computing the destination, a
    # crafted return_to would delete the hoojah and then 500 instead of falling back.
    return nil if uri.opaque.present?

    # An absolute URL is allowed ONLY when it targets this same host (same-origin);
    # a bare path has no host and is fine. Anything off-site → nil. The scheme
    # whitelist sits OUTSIDE the host branch too, so a host-less scheme can never slip
    # through. (`casecmp?` — host comparison is case-insensitive; over-rejecting a
    # same-site referer that only differs in case would be safe but needlessly strict.)
    return nil if uri.scheme && !%w[http https].include?(uri.scheme.downcase)
    return nil if uri.host.present? && !uri.host.casecmp?(request.host)

    # Nil-safe: an opaque URI is already rejected above, but keep `&.` so a future
    # host-only/pathless URI can't resurrect the crash.
    path = uri.path
    return nil unless path&.start_with?("/")
    return nil if path.start_with?("//") # e.g. an absolute "https://host//foo"
    path += "?#{uri.query}" if uri.query.present?

    # Don't send the user back to the record that just disappeared. Compare on the
    # PATH portion only — a show URL carrying a query (`/hoojah/slug?x=1`) must still
    # be recognised as the about-to-404 page and rejected.
    return nil if path.split("?").first == current_hujah_path.to_s.split("?").first
    path
  end

  # Secret ballot (2a/A7): the compact total-only label shown in place of the
  # per-stance breakdown when a hoojah is below k=3 total votes. One phrasing shared
  # across every surface (_vote_bars, _vote_hero, _child_card, _user_hujah) so they
  # can't drift. Zero reads "No votes yet"; otherwise "N vote"/"N votes".
  def vote_total_label(hujah)
    n = hujah.total_votes
    n.zero? ? "No votes yet" : "#{n} #{"vote".pluralize(n)}"
  end
end
