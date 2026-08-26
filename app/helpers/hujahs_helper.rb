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

  def format_body(text)
    tokenized = text.to_s
      .gsub(Hujah::MENTION_RE) { "#{MENTION_OPEN}@#{$1}#{MENTION_CLOSE}" }
      .gsub(Hujah::HASHTAG_RE) { "#{HASHTAG_OPEN}##{$1}#{HASHTAG_CLOSE}" }
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
      .delete(MENTION_OPEN + MENTION_CLOSE + HASHTAG_OPEN + HASHTAG_CLOSE)
      .html_safe
  end

  # Secret ballot (2a/A7): the compact total-only label shown in place of the
  # per-stance breakdown when a hoojah is below k=5 total votes. One phrasing shared
  # across every surface (_vote_bars, _vote_hero, _child_card, _user_hujah) so they
  # can't drift. Zero reads "No votes yet"; otherwise "N vote"/"N votes".
  def vote_total_label(hujah)
    n = hujah.total_votes
    n.zero? ? "No votes yet" : "#{n} #{"vote".pluralize(n)}"
  end
end
