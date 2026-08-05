// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Relative timestamps (<time data-local="time-ago" ...>). LocalTime.start() also
// re-processes elements inserted by Turbo Streams (its PageObserver watches the DOM).
import LocalTime from "local-time"
LocalTime.start()
