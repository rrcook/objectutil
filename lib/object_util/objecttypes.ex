defmodule Header do
  @derive Jason.Encoder
  defstruct [:segment_type, :object_id, :object_type, :object_module, :length, :num_objects]

  def parse(data) do
    <<
      name::binary-size(8),
      ext::binary-size(3),
      _sequence,
      type,
      length::16-little,
      _not_used_1,
      num_objects,
      _not_used_2,
      rest::binary
    >> = data

    {:ok,
     %Header{
       segment_type: :header,
       object_id: String.trim(name) <> "." <> String.trim(ext),
       object_type:
         ObjectTypes.enum_value(Map.get(ObjectTypes.object_type_map(), type, :unkown)),
       object_module: Map.get(ObjectTypes.object_mod_map(), type),
       length: length,
       num_objects: num_objects
     }, rest}
  end


end

defmodule ObjectTypes do
  use EnumType


  def enum_value(:unknown), do: :unknown
  def enum_value(enum_type), do: enum_type.value

  # Object Types
  defenum ObjectType do
    @moduledoc "The top level object types in a file"

    value PTO, :page_template_object do
    end

    value PFO, :page_format_object do
    end

    value PEO, :page_element_object do
    end

    value WEO, :window_object do
    end

    value PGO, :program_object do
    end
  end

  def object_type_map() do
    alias ObjectTypes.ObjectType

    %{
      0x00 => ObjectType.PFO,
      0x04 => ObjectType.PTO,
      0x08 => ObjectType.PEO,
      0x0C => ObjectType.PGO,
      0x0E => ObjectType.WEO
    }
  end

  def object_mod_map() do
    %{
      0x00 => PageFormatObject,
      0x04 => PageTemplateObject,
      0x08 => PageElementObject,
      0x0C => ProgramObject,
      0x0E => WindowElementObject
    }
  end

  def segment_type_map() do
    alias ObjectTypes.SegmentType

    %{
      0x01 => SegmentType.PGM_CALL,
      0x02 => SegmentType.FLD_LEVEL_PGM_CALL,
      0x04 => SegmentType.FIELD_DEFINITION,
      0x0A => SegmentType.CUSTOM_TEXT,
      0x0B => SegmentType.CUSTOM_CURSOR,
      0x20 => SegmentType.PAGE_ELEMENT_SELECTOR,
      0x21 => SegmentType.PAGE_ELEMENT_CALL,
      0x31 => SegmentType.PAGE_FORMAT_CALL,
      0x33 => SegmentType.PTN_DEFINITION,
      0x51 => SegmentType.PRES_DATA,
      0x52 => SegmentType.EMBEDDED_OBJECT,
      0x61 => SegmentType.PAGE_ELEMENT_CALL,
      0x71 => SegmentType.KWD_NAV
    }
  end

  def event_type_map() do
    alias ObjectTypes.EventType

    %{
      0x02 => EventType.INITIALIZER,
      0x04 => EventType.POST_PROCESSOR,
      0x08 => EventType.HELP_PROCESSOR
    }
  end

  def segment_mod_map() do
    %{
      0x01 => ProgramCallSegment,
      0x02 => FieldLevelProgramCallSegment,
      0x04 => FieldDefinitionSegment,
      0x0A => CustomTextSegment,
      0x0B => CustomCursorSegment,
      0x20 => PageElementSelectorSegment,
      0x21 => PageElementCallSegment,
      0x31 => PageFormatCallSegment,
      0x33 => PartitionDefinitionSegment,
      0x51 => PresentationDataSegment,
      0x52 => EmbeddedObjectSegment,
      0x61 => PageElementCallSegment,
      0x71 => KeywordNavigationSegment
    }
  end

  # Segment types
  defenum SegmentType do
    @moduledoc "Segment types inside object types"
    value CUSTOM_CURSOR, :custom_cursor do
    end

    value CUSTOM_TEXT, :custom_text do
    end

    value FIELD_DEFINITION, :field_definition do
    end

    value FLD_LEVEL_PGM_CALL, :field_level_program_call do
    end

    value KWD_NAV, :keyword_navigation do
    end

    value PAGE_ELEMENT_CALL, :page_element_call do
    end

    value PAGE_ELEMENT_SELECTOR, :page_element_selector do
    end

    value PAGE_FORMAT_CALL, :page_format_call do
    end

    value PTN_DEFINITION, :partition_definition do
    end

    value PRES_DATA, :presentation_data do
    end

    value PGM_CALL, :program_call do
    end

    value PGM_DATA, :program_data do
    end

    value EMBEDDED_OBJECT, :embedded_object do
    end
  end

  defenum PrefixType do
    value EXTERNAL_PFX, :external_prefix do
    end

    value EMBEDDED_PFX, :embedded_prefix do
    end
  end

  defenum EventType do
    value INITIALIZER, :initializer do
    end

    value POST_PROCESSOR, :post_processor do
    end

    value HELP_PROCESSOR, :help_processor do
    end
  end

  def prefix_type_map() do
    alias ObjectTypes.PrefixType

    %{
      0x0D => PrefixType.EXTERNAL_PFX,
      0x0F => PrefixType.EMBEDDED_PFX
    }
  end

  def extract_object_id(data) do
    <<
      name::binary-size(8),
      ext::binary-size(3),
      _not_used::binary-size(2),
      rest::binary
    >> = data

    {:ok, String.trim(name) <> "." <> String.trim(ext), rest}
  end

  def parse_parms(bytes_remaining, parms_list, data) when bytes_remaining <= 0 do
    {:ok, parms_list, data}
  end

  def parse_parms(bytes_remaining, parms_list, data) do
    <<
      length::16-big,
      parm_data::binary-size(length - 2),
      rest::binary
    >> = data

    parse_parms(bytes_remaining - length, parms_list ++ [parm_data], rest)
  end

  def parse_buffer(data) do
    # Find out the type of object from the 'header'
    {:ok, %Header{} = header, rest} = Header.parse(data)

    IO.inspect(header)

    os_list = build_list([header], rest)
    IO.inspect(os_list)
  end

  defp build_list(os_list, data) when byte_size(data) <= 0 do
    os_list
  end

  defp build_list(os_list, data) do
    {:ok, type, length} = Segment.segment_info(data)

    segment_module = Map.get(ObjectTypes.segment_mod_map(), type, :unknown)

    case segment_module do
      :unknown ->
        <<_dump_data::binary-size(length), rest>> = data
        build_list(os_list, rest)

      _ ->
        {:ok, segment, rest} = segment_module.parse(data)

        IO.inspect(segment)
        build_list(os_list ++ [segment], rest)
    end
  end
end

defmodule PageTemplateObject do
end

defmodule PageFormatObject do
end

defmodule PageElementObject do
end

defmodule WindowElementObject do
end

defmodule ProgramObject do
end

defmodule Segment do
  def segment_info(data) do
    <<
      type,
      length::16-little,
      _rest::binary
    >> = data

    {:ok, type, length}
  end
end

defmodule CustomCursorSegment do
end

defmodule CustomTextSegment do
end

defmodule FieldDefinitionSegment do
end

defmodule FieldLevelProgramCallSegment do
end

defmodule KeywordNavigationSegment do
  @derive Jason.Encoder
  defstruct [:segment_type, :segment_length, :guide_bfd, :current_keyword]

  def parse(data) do
    <<
      type,
      length::16-little,
      _prev_menu::binary-size(13),
      guide_bfd::binary-size(11),
      _blanks::binary-size(2),
      current_keyword::binary-size(13),
      rest::binary
    >> = data

    segment_type = ObjectTypes.enum_value(Map.get(ObjectTypes.segment_type_map(), type, :unkown))

    {:ok,
     %KeywordNavigationSegment{
       segment_type: segment_type,
       segment_length: length,
       guide_bfd: guide_bfd,
       current_keyword: String.trim(current_keyword)
     }, rest}
  end
end

defmodule PageElementCallSegment do
  @derive Jason.Encoder
  defstruct [
    :segment_type,
    :segment_length,
    :partition_id,
    :prefix_type,
    :object_id,
    :segment_offset
  ]

  def parse(data) do
    <<
      type,
      length::16-little,
      partition_id,
      _priority,
      prefix,
      rest1::binary
    >> = data

    segment_type = ObjectTypes.enum_value(Map.get(ObjectTypes.segment_type_map(), type, :unkown))

    case Map.get(ObjectTypes.prefix_type_map(), prefix) do
      ObjectTypes.PrefixType.EXTERNAL_PFX ->
        {:ok, object_id, rest} = ObjectTypes.extract_object_id(rest1)

        {:ok,
         %PageElementCallSegment{
           segment_type: segment_type,
           segment_length: length,
           partition_id: partition_id,
           prefix_type: ObjectTypes.enum_value(ObjectTypes.PrefixType.EXTERNAL_PFX),
           object_id: object_id
         }, rest}

      ObjectTypes.PrefixType.EMBEDDED_PFX ->
        <<
          offset::16-little,
          rest::binary
        >> = rest1

        {:ok,
         %PageElementCallSegment{
           segment_type: segment_type,
           segment_length: length,
           partition_id: partition_id,
           prefix_type: ObjectTypes.enum_value(ObjectTypes.PrefixType.EMBEDDED_PFX),
           segment_offset: offset
         }, rest}
    end
  end
end

defmodule PageElementSelectorSegment do
  @derive Jason.Encoder
  defstruct [
    :segment_type,
    :segment_length,
    :partition_id,
    :prefix_type,
    :object_id,
    :segment_offset,
    :parms
  ]

  def parse(data) do
    <<
      type,
      length::16-little,
      partition_id,
      _priority,
      prefix,
      rest1::binary
    >> = data

    segment_type = ObjectTypes.enum_value(Map.get(ObjectTypes.segment_type_map(), type, :unkown))

    {segment_struct, rest2} =
      case Map.get(ObjectTypes.prefix_type_map(), prefix) do
        ObjectTypes.PrefixType.EXTERNAL_PFX ->
          {:ok, object_id, rest2} = ObjectTypes.extract_object_id(rest1)

          {%PageElementSelectorSegment{
             segment_type: segment_type,
             segment_length: length,
             partition_id: partition_id,
             prefix_type: ObjectTypes.enum_value(ObjectTypes.PrefixType.EXTERNAL_PFX),
             object_id: object_id
           }, rest2}

        ObjectTypes.PrefixType.EMBEDDED_PFX ->
          <<
            offset::16-little,
            rest2::binary
          >> = rest1

          {%PageElementSelectorSegment{
             segment_type: segment_type,
             segment_length: length,
             partition_id: partition_id,
             prefix_type: ObjectTypes.enum_value(ObjectTypes.PrefixType.EMBEDDED_PFX),
             segment_offset: offset
           }, rest2}
      end

    <<parms_length::16-big, rest3::binary>> = rest2
    {:ok, parms_list, rest} = ObjectTypes.parse_parms(parms_length - 2, [], rest3)

    # {:ok, %PageElementSelectorSegment{segment_struct | parms: parms_list}, rest}
    {:ok, %PageElementSelectorSegment{segment_struct | parms: "FIXME"}, rest}
  end
end

defmodule PageFormatCallSegment do
  @derive Jason.Encoder
  defstruct [:segment_type, :segment_length, :prefix_type, :object_id, :segment_offset]

  def parse(data) do
    <<
      type,
      length::16-little,
      prefix,
      rest1::binary
    >> = data

    segment_type = ObjectTypes.enum_value(Map.get(ObjectTypes.segment_type_map(), type, :unkown))

    case Map.get(ObjectTypes.prefix_type_map(), prefix) do
      ObjectTypes.PrefixType.EXTERNAL_PFX ->
        {:ok, object_id, rest} = ObjectTypes.extract_object_id(rest1)

        {:ok,
         %PageFormatCallSegment{
           segment_type: segment_type,
           segment_length: length,
           prefix_type: ObjectTypes.PrefixType.EXTERNAL_PFX.value(),
           object_id: object_id
         }, rest}

      ObjectTypes.PrefixType.EMBEDDED_PFX ->
        <<
          offset::16-little,
          rest::binary
        >> = rest1

        {:ok,
         %PageFormatCallSegment{
           segment_type: segment_type,
           segment_length: length,
           prefix_type: ObjectTypes.PrefixType.EMBEDDED_PFX.value(),
           segment_offset: offset
         }, rest}
    end
  end
end

defmodule PartitionDefinitionSegment do
end

defmodule PresentationDataSegment do
end

defmodule ProgramCallSegment do
  @derive Jason.Encoder
  defstruct [
    :segment_type,
    :segment_length,
    :event_type,
    :prefix_type,
    :object_id,
    :segment_offset,
    :parms
  ]

  def parse(data) do
    <<
      segment,
      length::16-little,
      event,
      prefix,
      rest1::binary
    >> = data

    segment_type =
      ObjectTypes.enum_value(Map.get(ObjectTypes.segment_type_map(), segment, :unkown))

    event_type = ObjectTypes.enum_value(Map.get(ObjectTypes.event_type_map(), event, :unkown))

    {segment_struct, rest2} =
      case Map.get(ObjectTypes.prefix_type_map(), prefix) do
        ObjectTypes.PrefixType.EXTERNAL_PFX ->
          {:ok, object_id, rest2} = ObjectTypes.extract_object_id(rest1)

          {%ProgramCallSegment{
             segment_type: segment_type,
             segment_length: length,
             event_type: event_type,
             prefix_type: ObjectTypes.PrefixType.EXTERNAL_PFX.value(),
             object_id: object_id
           }, rest2}

        ObjectTypes.PrefixType.EMBEDDED_PFX ->
          <<
            offset::16-little,
            rest2::binary
          >> = rest1

          {%ProgramCallSegment{
             segment_type: segment_type,
             segment_length: length,
             event_type: event_type,
             prefix_type: ObjectTypes.PrefixType.EMBEDDED_PFX.value(),
             segment_offset: offset
           }, rest2}
      end

    <<parms_length::16-big, rest3::binary>> = rest2
    {:ok, parms_list, rest} = ObjectTypes.parse_parms(parms_length - 2, [], rest3)

    # {:ok, %ProgramCallSegment{segment_struct | parms: parms_list}, rest}
    {:ok, %ProgramCallSegment{segment_struct | parms: "FIXME"}, rest}
  end
end

defmodule EmbeddedObjectSegment do
  @derive Jason.Encoder
  defstruct [:segment_type, :segment_length, :embedded_data]

  def parse(data) do
    <<
      segment,
      length::16-little,
      rest1::binary
    >> = data

    segment_type =
      ObjectTypes.enum_value(Map.get(ObjectTypes.segment_type_map(), segment, :unkown))

    # 'length' includes the segment type and length, so the length of the data
    # is 3 bytes less than 'length'
    <<
      embedded_data::binary-size(length - 3),
      rest::binary
    >> = rest1

    {:ok,
     %EmbeddedObjectSegment{
       segment_type: segment_type,
       segment_length: length,
       # embedded_data: embedded_data
       embedded_data: "FIXME"
     }, rest}
  end
end
