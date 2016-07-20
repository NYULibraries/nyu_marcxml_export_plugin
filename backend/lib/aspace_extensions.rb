module ExportHelpers

  ASpaceExport::init

  def generate_marc(id)
    obj = resolve_references(Resource.to_jsonmodel(id),
    ['repository', 'linked_agents', 'subjects', 'instances',
      'tree'])
      repo_code = obj['repository']['_resolved']['repo_code']
      @top_level_containers = nil
      @nested_containers = nil
      top_level = get_top_resource_level_uris(obj['instances']) unless repo_code =~ /ASPACE/
      @top_level_containers = get_locations(top_level) if top_level
      # getting all ids for archival objects
      # at the lowest level, i.e. if there
      # is an array of hashes and the hashes
      # are nested, grabbing the ids from the
      # lowest level
      related_objects_ids = get_related_object_ids(obj)

      # grabbing containers for those ids
      containers = get_related_containers(related_objects_ids) if related_objects_ids

      # get top containers
      if containers
        top_containers = get_top_containers(containers)
        @nested_containers = get_locations(top_containers)
      end
      tc_hash = combine_everything
      obj['top_containers'] = tc_hash unless tc_hash.nil?
      marc = ASpaceExport.model(:marc21).from_resource(JSONModel(:resource).new(obj))
      ASpaceExport::serialize(marc)

    end

    def combine_everything
      hash = nil
      if @top_level_containers && @nested_containers
        hash = @top_level_containers.merge(@nested_containers)
      elsif @top_level_containers.nil? && @nested_containers
        hash = @nested_containers
      elsif @top_level_containers && @nested_containers.nil?
        hash = @top_level_containers
      end
      hash
    end

    def get_top_resource_level_uris(instances)
      tc_hash = {}
      instances.each { |i|
        url = i['sub_container']['top_container']['ref']
        id = get_top_container_id(url)
        # can just get the hash by passig nil
        top_container = resolve_references(TopContainer.to_jsonmodel(id),nil)
        hash = {indicator: top_container['indicator'] }
        barcode = top_container['barcode']
        tc_hash[id] = barcode.nil? ? hash : hash.merge({ barcode: barcode })
      }
      tc_hash
    end
    # getting ids of all archival objects
    # that might contain top container references
    def get_related_object_ids(obj)
      object_ids = []
      objects = obj['tree']['_resolved']['children']
      objects.each { |object|
        # if nested hash
        if object['has_children']
          # send array of those hashes
          get_object_ids(object['children'],object_ids)
        else
          # not a nested hash
          object_ids << object['id']
        end
      }
      object_ids
    end

    # recursively iterating through
    # n nested levels of archival object hashes
    def get_object_ids(tree,ids)
      tree.each { |items|
        if items["has_children"]
          get_object_ids(items['children'],ids)
        else
          ids << items['id']
        end
      }
    end

    # get archival objects and top container tree
    def get_related_containers(related_objects)
      related_containers = []
      related_objects.each { |r|
        obj = resolve_references(ArchivalObject.to_jsonmodel(r),
        ['top_container'])
        related_containers << obj['instances']
      }
      related_containers
    end

    def get_top_container_id(url)
      info = url.split('/')[4]
      info.to_i
    end

    # returns a hash of top container metadata
    def get_top_container_metadata(data)
      tc_id = get_top_container_id(data['ref'])
      barcode =  data['_resolved']['barcode']
      hash = {id: tc_id, indicator: data['_resolved']['indicator'] }
      # if no barcode, just get indicator,
      # else, merge barcode with indicator in one hash
      metadata = barcode.nil? ? hash : hash.merge({ barcode: barcode })
    end

    def get_top_containers(related_containers)
      top_containers = {}
      related_containers.each{ |containers|
        containers.each{ |t|
          if t['sub_container']
            top_container_tree = t['sub_container']['top_container']
            tc_info = get_top_container_metadata(top_container_tree)
            top_containers[tc_info[:id]] = tc_info.reject!{ |k,v| k == :id }
          end
        }
      }
      top_containers
    end

    # location metadata
    def get_location_metadata(id)
      obj = resolve_references(TopContainer.to_jsonmodel(id),
      ['container_locations'])
      location = obj['container_locations'][0]
      location['_resolved']['building'] if location
    end

    def get_locations(top_containers)
      location = {}
      tc = top_containers.dup
      top_containers.each_key { |id|
        # if there's location information
        # continue processing
        building = get_location_metadata(id)
        if  building
          location = {location: building}
          tc[id] = top_containers[id].merge(location)
        end
      }
      tc
    end
  end

  class MARCModel < ASpaceExport::ExportModel
    attr_reader :aspace_record, :top_containers
    attr_accessor :controlfields

    def initialize(obj)
      @datafields = {}
      @controlfields = {}
      @aspace_record = obj
    end


    def self.from_aspace_object(obj)
      self.new(obj)
    end



  end
