require_relative 'lib/aspace_extensions'
require_relative 'lib/marc_custom_field_serialize'
require_relative 'lib/nyu_custom_tag'
require_relative 'lib/nyu_custom_serializer_marc21'


MARCSerializer.add_decorator(MARCCustomFieldSerialize)
