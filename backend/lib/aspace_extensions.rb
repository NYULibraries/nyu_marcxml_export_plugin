require 'net/http/persistent'
module ExportHelpers

  ASpaceExport::init

  def generate_marc(id, include_unpublished = false)
    opts = {:include_unpublished => include_unpublished}

    references = ['repository', 'linked_agents', 'subjects', 'instances', 'tree']
    @obj = resolve_references(Resource.to_jsonmodel(id), references)

    tc_hash = process_top_containers
    @obj['top_containers'] = tc_hash unless tc_hash.nil?

    resource = JSONModel(:resource).new(@obj)
    JSONModel::set_publish_flags!(resource)
    marc = ASpaceExport.model(:marc21).from_resource(resource, opts)

    ASpaceExport::serialize(marc)
  end

  def find_top_containers
    repo_id = @obj['repository']['_resolved']['uri'].split("/")[2]
    resource_id = @obj['uri']
    search_params = {}
    search_params['page'] = 1
    search_params[:type] = ['top_container']
    search_params[:filter_term] = [{"collection_uri_u_sstr" => resource_id}.to_json]
    top_container_results = nil
    TopContainer.search_stream(search_params,repo_id) do |response|
      top_container_results = JSON.parse(response.body)
    end
    top_container_results
  end

  def process_top_containers
    top_container_results = find_top_containers
    tc_info = {}
    top_containers = top_container_results['response']['docs']

    top_containers.each { |tc|
      data = JSON.parse(tc['json'])
      id = data['uri'] # top container uri
      indicator = data['indicator']
      hash = { indicator: data['indicator'] }
      if data['barcode']
        barcode = { barcode: data['barcode'] }
        hash = hash.merge(barcode)
      end
      tc_info[id] = hash

      # Checking for nil location
      if tc["location_display_string_u_sstr"] then
        location = tc["location_display_string_u_sstr"][0]
        tc_info[id].merge!({location: location})
      end
      #location = tc["location_display_string_u_sstr"][0]
      # The other way to get the location is through the location model
      # location = data['container_locations'][0]
      # location['_resolved']['title']
      # attached to tc
      # tc["location_display_string_u_sstr"]
      # Unsure about which is more stable:
      # whether to traverse the location model
      # or the solr schema
      # possibly the solr schema since it is also attached
      # to the PUI
      #tc_info[id].merge!({location: location}) if location

    }
    tc_info
  end
end

class MARCModel < ASpaceExport::ExportModel
  attr_reader :aspace_record, :top_containers
  attr_accessor :controlfields
  def initialize(obj, opts = {include_unpublished: false})
    @datafields = {}
    @controlfields = {}
    @include_unpublished = opts[:include_unpublished]
    @aspace_record = obj
  end

  def include_unpublished?
    @include_unpublished
  end

  def self.from_aspace_object(obj, opts = {})
    self.new(obj, opts)
  end
end
