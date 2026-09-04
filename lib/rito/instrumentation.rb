# frozen_string_literal: true

module Rito
  # Emits `request.rito` events via ActiveSupport::Notifications when
  # ActiveSupport is available; a no-op otherwise.
  module Instrumentation
    EVENT = 'request.rito'

    class << self
      def emit(payload)
        return unless defined?(ActiveSupport::Notifications)

        ActiveSupport::Notifications.instrument(EVENT, payload)
      end
    end
  end
end
