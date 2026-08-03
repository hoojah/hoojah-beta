# Prepend clang shim so every native gem build inherits the -Wno-error relaxations
# needed to compile old (Rails 6.0-era) C extensions under modern clang on arm64.
export PATH="$PWD/.cc-shim:$PATH"
