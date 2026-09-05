# frozen_string_literal: true

module Rito
  module RateLimiting
    # Tracks windows learned from X-App-Rate-Limit / X-Method-Rate-Limit headers
    # and blocks callers before limits are hit.
    class Bucket
      DEFAULT_BACKOFF = 1
      MAX_BACKOFF = 32
      JITTER = 0.5

      def initialize(clock:, sleeper: Kernel.method(:sleep))
        @clock = clock
        @sleeper = sleeper
        @mutex = Mutex.new
        @windows = []
        @blocked_until = nil
        @limited_streak = 0
      end

      def apply!(limits:, counts:, limited: false)
        @mutex.synchronize do
          now = @clock.call
          if limits.any?
            counts_by_window = counts.to_h { |count, window| [window, count] }
            @windows = limits.map do |limit, window|
              previous = @windows.find { |w| w[:window] == window && w[:reset_at] > now }
              {
                limit: limit,
                window: window,
                reset_at: previous&.fetch(:reset_at) || now + window,
                count: [counts_by_window.fetch(window, 0), previous&.fetch(:count) || 0].max
              }
            end
          end
          @limited_streak = 0 unless limited
        end
      end

      # Blocks the bucket. When retry_after is nil (missing Retry-After header),
      # falls back to exponential backoff with jitter based on the streak of
      # consecutive 429s.
      def limit_block!(retry_after)
        @mutex.synchronize do
          now = @clock.call
          @limited_streak = [@limited_streak + 1, 6].min
          delay = retry_after || [2**(@limited_streak - 1) * DEFAULT_BACKOFF, MAX_BACKOFF].min
          delay += rand * JITTER unless retry_after
          until_time = now + delay
          @blocked_until = until_time if @blocked_until.nil? || @blocked_until < until_time
        end
      end

      def delay
        @mutex.synchronize { delay_unlocked }
      end

      def consume!
        @mutex.synchronize { @windows.each { |window| window[:count] += 1 } }
      end

      def wait_until_allowed!
        loop do
          wait = @mutex.synchronize do
            delay_unlocked.tap do |value|
              @windows.each { |window| window[:count] += 1 } if value.zero?
            end
          end
          return if wait.zero?

          @sleeper.call(wait + 0.001)
        end
      end

      def blocked?
        @mutex.synchronize do
          @blocked_until && @blocked_until > @clock.call
        end
      end

      private

      def delay_unlocked
        now = @clock.call
        @windows.each do |window|
          next if window[:reset_at] > now

          window[:count] = 0
          window[:reset_at] = now + window[:window]
        end
        delays = @windows.filter_map do |window|
          window[:reset_at] - now if window[:count] >= window[:limit]
        end
        [0, (@blocked_until || now) - now, *delays].max
      end
    end
  end
end
