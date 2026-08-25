# invisible_captcha guards the sign-up form (Users::RegistrationsController) with a
# hidden `subtitle` honeypot AND a submit-speed timestamp check. The gem's default
# timestamp_threshold is 4 seconds: any submit faster than that is treated as a bot
# and the create is silently rejected with a bare `redirect_back` (302).
#
# Four seconds is long enough to catch real people — password managers and browser
# autofill fill all five fields and submit in under a second, and even a fast typist
# clears it. When they tripped it, invisible_captcha halted the filter chain before
# Devise ran, so the account was never created and (because the layout showed no
# flash) the form just reloaded blank: "nothing happens after I click Sign up."
#
# We keep the timestamp check as a cheap bot filter but lower the floor to 1 second,
# which no human filling a five-field form can beat while trivial instant-submit bots
# still trip it. The honeypot remains the primary defense. spec/requests/signup_flow_spec.rb
# pins this value so the 4s default can't creep back in.
InvisibleCaptcha.timestamp_threshold = 1
