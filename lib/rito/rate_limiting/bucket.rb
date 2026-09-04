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

      def apply!(limits:, counts:)
        @mutex.synchronize do
          now = @clock.call
          if limits.any?
            counts_by_window = counts.to_h { |count, window| [window, count] }
            @windows = limits.map do |limit, window|
              previous = @windows.find { |w| w[:window] == window && w[:reset_at] > now }
              {
                limit: limit,
                window: window,
                reset_at: now + window,
                count: counts_by_window.fetch(window) { previous&.fetch(:count) || 0 }
              }
            end
          end
          @limited_streak = 0
        end
      end

      # Blocks the bucket. When retry_after is nil (missing Retry-After header),
      # falls back to exponential backoff with jitter based on the streak of
      # consecutive 429s.
      def limit_block!(retry_after)
        @mutex.synchronize do
          now = @clock.call
          @limited_streak += 1
          delay = retry_after || [@limited_streak * DEFAULT_BACKOFF, MAX_BACKOFF].min
          delay += rand * JITTER
          until_time = now + delay
          @blocked_until = until_time if @blocked_until.nil? || @blocked_until < until_time
        end
      end

      def wait_until_allowed!
        loop do
          delay = nil
          @mutex.synchronize do
            now = @clock.call
            if @blocked_until && @blocked_until > now
              delay = @blocked_until - now
            else
              @windows.reject! { |w| w[:reset_at] <= now }
              violating = @windows.find { |w| w[:count] >= w[:limit] }
              if violating
                delay = violating[:reset_at] - now
              else
                @windows.each { |w| w[:count] += 1 }
                return
              end
            end
          end
          @sleeper.call(delay + 0.001)
        end
      end

      def blocked?
        @mutex.synchronize do
          @blocked_until && @blocked_until > @clock.call
        end
      end
    end
  end
end
