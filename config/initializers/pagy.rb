# Pagy configuration.
#
# NOTE / DEVIATION FROM PLAN: the plan (Task 4.1) was written against the classic
# Pagy API (`require 'pagy/extras/countless'`, `Pagy::DEFAULT[:limit]`,
# `include Pagy::Backend`, `pagy_countless(...)`). The pinned gem is pagy ~> 43.6,
# whose API was fully reworked:
#   * countless pagination is built in (no `extras/countless` file) and is invoked
#     as `pagy(:countless, collection)` via the `Pagy::Method` mixin.
#   * defaults live in the frozen `Pagy::DEFAULT`; per-app overrides go in
#     `Pagy::OPTIONS`.
# The countless load-more behaviour and `@pagy.next` contract the plan relies on
# are preserved.
require "pagy"

# 15 top-level hujahs per feed page (matches the request spec's expectation).
Pagy::OPTIONS[:limit] = 15
