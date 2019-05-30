require 'fedex/request/base'

module Fedex
  module Request
    class Rate < Base
      # Sends post request to Fedex web service and parse the response, a Rate object is created if the response is successful
      def process_request
        api_response = self.class.post(api_url, :body => build_xml)
        puts api_response if @debug
        response = parse_response(api_response)
        if success?(response)
          rate_details = [response[:rate_reply][:rate_reply_details][:rated_shipment_details]].flatten.first[:shipment_rate_detail]
          Fedex::Rate.new(rate_details)
        else
          if response[:rate_reply]
            notifications = response[:rate_reply][:notifications]
            notification = [notifications].flatten.first
            error_message = notification[:message]
            error_code = notification[:code]
          else
            error_message = api_response["Fault"]["detail"]["fault"]["reason"]
            error_code = response["Fault"]["detail"]["fault"]["errorCode"]
          end rescue $1
          raise RateError.new(error_message, code: error_code)
        end
      end

      private

      # Add information for shipments
      def add_requested_shipment(xml)
        xml.RequestedShipment{
          xml.DropoffType @shipping_options[:drop_off_type] ||= "REGULAR_PICKUP"
          xml.ServiceType service_type
          xml.PackagingType @shipping_options[:packaging_type] ||= "YOUR_PACKAGING"
          add_shipper(xml)
          add_recipient(xml)
          add_shipping_charges_payment(xml)
          add_customs_clearance(xml) if @customs_clearance
          xml.RateRequestTypes "LIST"
          add_packages(xml)
        }
      end

      # Build xml Fedex Web Service request
      def build_xml
        builder = Nokogiri::XML::Builder.new do |xml|
          xml[:soapenv].Envelope(
            'xmlns:soapenv' => "http://schemas.xmlsoap.org/soap/envelope/",
            'xmlns:v24' => "http://fedex.com/ws/rate/v24"
          ) {
            xml['soapenv'].Header
            xml['soapenv'].Body {
              xml[:v24].RateRequest{
                add_web_authentication_detail(xml)
                add_client_detail(xml)
                add_version(xml)
                add_requested_shipment(xml)
              }
            }
          }
        end
        builder.doc.root.to_xml
      end

      def service
        { :id => 'crs', :version => 24 }
      end

      # Successful request
      def success?(response)
        response[:rate_reply] &&
          %w{SUCCESS WARNING NOTE}.include?(response[:rate_reply][:highest_severity])
      end

    end
  end
end
