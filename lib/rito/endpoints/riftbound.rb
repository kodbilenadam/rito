# frozen_string_literal: true

module Rito
  module Endpoints
    class Riftbound < Base
      ROUTING = :regional

      def contents(locale: nil, region: nil)
        params = {}
        params['locale'] = locale if locale
        get('/riftbound/content/v1/contents', region, params: params)
      end
    end
  end
end
