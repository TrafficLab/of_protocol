%%------------------------------------------------------------------------------
%% Copyright 2012 FlowForwarding.org
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%-----------------------------------------------------------------------------

%% @author Erlang Solutions Ltd. <openflow@erlang-solutions.com>
%% @author Konrad Kaplita <konrad.kaplita@erlang-solutions.com>
%% @author Krzysztof Rutka <krzysztof.rutka@erlang-solutions.com>
%% @copyright 2012 FlowForwarding.org
%% @doc OpenFlow Protocol 1.3 (4) encoding implementation.
%% @private
-module(ofp_v4_encode).

-export([do/1]).

-include("of_protocol.hrl").
-include("ofp_v4.hrl").

%%------------------------------------------------------------------------------
%% API functions
%%------------------------------------------------------------------------------

%% @doc Actual encoding of the message.
-spec do(Message :: ofp_message()) -> binary().
do(#ofp_message{version = Version, xid = Xid, body = Body}) ->
    BodyBin = encode_body(Body),
    TypeInt = type_int(Body),
    Length = ?OFP_HEADER_SIZE + size(BodyBin),
    <<Version:8, TypeInt:8, Length:16, Xid:32, BodyBin/bytes>>.

%%------------------------------------------------------------------------------
%% Encode functions
%%------------------------------------------------------------------------------

%% Structures ------------------------------------------------------------------

encode_struct(#ofp_match{fields = Fields}) ->
    FieldsBin = encode_list(Fields),
    FieldsLength = size(FieldsBin),
    Length = FieldsLength + ?MATCH_SIZE - 4,
    Padding = ofp_utils:padding(Length, 8) * 8,
    <<1:16, Length:16, FieldsBin/bytes, 0:Padding>>;
encode_struct(#ofp_field{class = Class, name = Field, has_mask = HasMask,
                         value = Value, mask = Mask}) ->
    ClassInt = ofp_v4_enum:to_int(oxm_class, Class),
    FieldInt = ofp_v4_enum:to_int(oxm_ofb_match_fields, Field),
    BitLength = ofp_v4_map:tlv_length(Field),
    case Class of
        openflow_basic ->
            Value2 = ofp_utils:cut_bits(Value, BitLength);
        _ ->
            Value2 = Value
    end,
    case HasMask of
        true ->
            HasMaskInt = 1,
            case Class of
                openflow_basic ->
                    Mask2 = ofp_utils:cut_bits(Mask, BitLength);
                _ ->
                    Mask2 = Mask
            end,
            Rest = <<Value2/bytes, Mask2/bytes>>,
            Len2 = byte_size(Value2) * 2;
        false ->
            HasMaskInt = 0,
            Rest = <<Value2/bytes>>,
            Len2 = byte_size(Value2)
    end,
    <<ClassInt:16, FieldInt:7, HasMaskInt:1, Len2:8, Rest/bytes>>;

encode_struct(#ofp_port{port_no = PortNo, hw_addr = HWAddr, name = Name,
                        config = Config, state = State, curr = Curr,
                        advertised = Advertised, supported = Supported,
                        peer = Peer, curr_speed = CurrSpeed,
                        max_speed = MaxSpeed}) ->
    PortNoInt = get_id(port_no, PortNo),
    NameBin = ofp_utils:encode_string(Name, ?OFP_MAX_PORT_NAME_LEN),
    ConfigBin = flags_to_binary(port_config, Config, 4),
    StateBin = flags_to_binary(port_state, State, 4),
    CurrBin = flags_to_binary(port_features, Curr, 4),
    AdvertisedBin = flags_to_binary(port_features, Advertised, 4),
    SupportedBin = flags_to_binary(port_features, Supported, 4),
    PeerBin = flags_to_binary(port_features, Peer, 4),
    <<PortNoInt:32, 0:32, HWAddr:?OFP_ETH_ALEN/bytes, 0:16,
      NameBin:?OFP_MAX_PORT_NAME_LEN/bytes,
      ConfigBin:4/bytes, StateBin:4/bytes, CurrBin:4/bytes,
      AdvertisedBin:4/bytes, SupportedBin:4/bytes,
      PeerBin:4/bytes, CurrSpeed:32, MaxSpeed:32>>;

encode_struct(#ofp_packet_queue{queue_id = Queue, port_no = Port,
                                properties = Props}) ->
    PropsBin = encode_list(Props),
    Length = ?PACKET_QUEUE_SIZE + size(PropsBin),
    <<Queue:32, Port:32, Length:16, 0:48, PropsBin/bytes>>;
encode_struct(#ofp_queue_prop_min_rate{rate = Rate}) ->
    PropertyInt = ofp_v4_enum:to_int(queue_properties, min_rate),
    <<PropertyInt:16, ?QUEUE_PROP_MIN_RATE_SIZE:16, 0:32, Rate:16, 0:48>>;
encode_struct(#ofp_queue_prop_max_rate{rate = Rate}) ->
    PropertyInt = ofp_v4_enum:to_int(queue_properties, max_rate),
    <<PropertyInt:16, ?QUEUE_PROP_MAX_RATE_SIZE:16, 0:32, Rate:16, 0:48>>;
encode_struct(#ofp_queue_prop_experimenter{experimenter = Experimenter,
                                           data = Data}) ->
    Length = ?QUEUE_PROP_EXPERIMENTER_SIZE + byte_size(Data),
    PropertyInt = ofp_v4_enum:to_int(queue_properties, experimenter),
    <<PropertyInt:16, Length:16, 0:32, Experimenter:32, 0:32, Data/bytes>>;

encode_struct(#ofp_meter_band_drop{type = drop, rate = Rate,
                                   burst_size = BurstSize}) ->
    TypeInt = ofp_v4_enum:to_int(meter_band_type, drop),
    <<TypeInt:16, ?METER_BAND_SIZE:16, Rate:32, BurstSize:32, 0:32>>;
encode_struct(#ofp_meter_band_dscp_remark{type = dscp_remark, rate = Rate,
                                          burst_size = BurstSize,
                                          prec_level = PrecLevel}) ->
    TypeInt = ofp_v4_enum:to_int(meter_band_type, dscp_remark),
    <<TypeInt:16, ?METER_BAND_SIZE:16, Rate:32, BurstSize:32,
      PrecLevel:8, 0:24>>;
encode_struct(#ofp_meter_band_experimenter{type = experimenter, rate = Rate,
                                           burst_size = BurstSize,
                                           experimenter = Experimenter}) ->
    TypeInt = ofp_v4_enum:to_int(meter_band_type, experimenter),
    <<TypeInt:16, ?METER_BAND_SIZE:16, Rate:32, BurstSize:32, Experimenter:32>>.

encode_async_masks({PacketInMask1, PacketInMask2},
                   {PortStatusMask1, PortStatusMask2},
                   {FlowRemovedMask1, FlowRemovedMask2}) ->
    PIn1 = flags_to_binary(packet_in_reason, PacketInMask1, 4),
    PIn2 = flags_to_binary(packet_in_reason, PacketInMask2, 4),
    PS1 = flags_to_binary(port_reason, PortStatusMask1, 4),
    PS2 = flags_to_binary(port_reason, PortStatusMask2, 4),
    FR1 = flags_to_binary(flow_removed_reason, FlowRemovedMask1, 4),
    FR2 = flags_to_binary(flow_removed_reason, FlowRemovedMask2, 4),
    <<PIn1:32/bits, PIn2:32/bits, PS1:32/bits, PS2:32/bits,
      FR1:32/bits, FR2:32/bits>>.

%%% Messages -------------------------------------------------------------------

encode_body(#ofp_hello{}) ->
    <<>>;
encode_body(#ofp_error_msg{type = Type, code = Code, data = Data}) ->
    TypeInt = ofp_v4_enum:to_int(error_type, Type),
    CodeInt = ofp_v4_enum:to_int(Type, Code),
    <<TypeInt:16, CodeInt:16, Data/bytes>>;
encode_body(#ofp_error_msg_experimenter{exp_type = ExpTypeInt,
                                        experimenter = Experimenter,
                                        data = Data}) ->
    TypeInt = ofp_v4_enum:to_int(error_type, experimenter),
    <<TypeInt:16, ExpTypeInt:16, Experimenter:32, Data/bytes>>;
encode_body(#ofp_echo_request{data = Data}) ->
    Data;
encode_body(#ofp_echo_reply{data = Data}) ->
    Data;
encode_body(#ofp_experimenter{experimenter = Experimenter,
                              exp_type = Type, data = Data}) ->
    <<Experimenter:32, Type:32, Data/bytes>>;
encode_body(#ofp_features_request{}) ->
    <<>>;
encode_body(#ofp_features_reply{datapath_mac = DataPathMac,
                                datapath_id = DataPathID, n_buffers = NBuffers,
                                n_tables = NTables, auxiliary_id = AuxId,
                                capabilities = Capabilities}) ->
    CapaBin = flags_to_binary(capabilities, Capabilities, 4),
    <<DataPathMac:48/bits, DataPathID:16, NBuffers:32,
      NTables:8, AuxId:8, 0:16, CapaBin:32/bits, 0:32>>;
encode_body(#ofp_get_config_request{}) ->
    <<>>;
encode_body(#ofp_get_config_reply{flags = Flags, miss_send_len = Miss}) ->
    FlagsBin = flags_to_binary(config_flags, Flags, 2),
    <<FlagsBin:16/bits, Miss:16>>;
encode_body(#ofp_set_config{flags = Flags, miss_send_len = Miss}) ->
    FlagsBin = flags_to_binary(config_flags, Flags, 2),
    <<FlagsBin:16/bits, Miss:16>>;
encode_body(#ofp_packet_in{buffer_id = BufferId, reason = Reason,
                           table_id = TableId, cookie = Cookie,
                           match = Match, data = Data}) ->
    BufferIdInt = get_id(buffer, BufferId),
    ReasonInt = ofp_v4_enum:to_int(packet_in_reason, Reason),
    MatchBin = encode_struct(Match),
    TotalLen = byte_size(Data),
    <<BufferIdInt:32, TotalLen:16, ReasonInt:8, TableId:8, Cookie:64/bits,
      MatchBin/bytes, 0:16, Data/bytes>>;
encode_body(#ofp_flow_removed{cookie = Cookie, priority = Priority,
                              reason = Reason, table_id = TableId,
                              duration_sec = Sec, duration_nsec = NSec,
                              idle_timeout = Idle, hard_timeout = Hard,
                              packet_count = PCount, byte_count = BCount,
                              match = Match}) ->
    ReasonInt = ofp_v4_enum:to_int(flow_removed_reason, Reason),
    MatchBin = encode_struct(Match),
    <<Cookie:8/bytes, Priority:16, ReasonInt:8, TableId:8, Sec:32, NSec:32,
      Idle:16, Hard:16, PCount:64, BCount:64, MatchBin/bytes>>;
encode_body(#ofp_port_status{reason = Reason, desc = Port}) ->
    ReasonInt = ofp_v4_enum:to_int(port_reason, Reason),
    PortBin = encode_struct(Port),
    <<ReasonInt:8, 0:56, PortBin/bytes>>;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

encode_body(#ofp_barrier_request{}) ->
    <<>>;
encode_body(#ofp_barrier_reply{}) ->
    <<>>;
encode_body(#ofp_queue_get_config_request{port = Port}) ->
    PortInt = get_id(port_no, Port),
    <<PortInt:32, 0:32>>;
encode_body(#ofp_queue_get_config_reply{port = Port, queues = Queues}) ->
    PortInt = get_id(port_no, Port),
    QueuesBin = encode_list(Queues),
    <<PortInt:32, 0:32, QueuesBin/bytes>>;
encode_body(#ofp_role_request{role = Role, generation_id = Gen}) ->
    RoleInt = ofp_v4_enum:to_int(controller_role, Role),
    <<RoleInt:32, 0:32, Gen:64>>;
encode_body(#ofp_role_reply{role = Role, generation_id = Gen}) ->
    RoleInt = ofp_v4_enum:to_int(controller_role, Role),
    <<RoleInt:32, 0:32, Gen:64>>;

encode_body(#ofp_get_async_request{}) ->
    <<>>;
encode_body(#ofp_get_async_reply{packet_in_mask = PacketInMask,
                                 port_status_mask = PortStatusMask,
                                 flow_removed_mask = FlowRemovedMask}) ->
    encode_async_masks(PacketInMask, PortStatusMask, FlowRemovedMask);
encode_body(#ofp_set_async{packet_in_mask = PacketInMask,
                           port_status_mask = PortStatusMask,
                           flow_removed_mask = FlowRemovedMask}) ->
    encode_async_masks(PacketInMask, PortStatusMask, FlowRemovedMask);
encode_body(#ofp_meter_mod{command = Command,
                           flags = Flag,
                           meter_id = MeterId,
                           bands = Bands}) ->
    CommandInt = get_id(meter_mod_command, Command),
    FlagsInt = get_id(meter_flag, Flag),
    MeterIdInt = get_id(meter_id, MeterId),
    BandsBin = encode_list(Bands),
    <<CommandInt:16, FlagsInt:16, MeterIdInt:32, BandsBin/bytes>>;
encode_body(Other) ->
    throw({bad_message, Other}).

%%------------------------------------------------------------------------------
%% Helper functions
%%------------------------------------------------------------------------------

flags_to_binary(Type, Flags, Size) ->
    ofp_utils:flags_to_binary(ofp_v4_enum, Type, Flags, Size).

get_id(Enum, Value) ->
    ofp_utils:get_enum_value(ofp_v4_enum, Enum, Value).

-spec encode_list(list()) -> binary().
encode_list(List) ->
    ofp_utils:encode_list(fun encode_struct/1, List, <<>>).

-spec type_int(ofp_message_body()) -> integer().
type_int(#ofp_hello{}) ->
    ofp_v4_enum:to_int(type, hello);
type_int(#ofp_error_msg{}) ->
    ofp_v4_enum:to_int(type, error);
type_int(#ofp_error_msg_experimenter{}) ->
    ofp_v4_enum:to_int(type, error);
type_int(#ofp_echo_request{}) ->
    ofp_v4_enum:to_int(type, echo_request);
type_int(#ofp_echo_reply{}) ->
    ofp_v4_enum:to_int(type, echo_reply);
type_int(#ofp_experimenter{}) ->
    ofp_v4_enum:to_int(type, experimenter);
type_int(#ofp_features_request{}) ->
    ofp_v4_enum:to_int(type, features_request);
type_int(#ofp_features_reply{}) ->
    ofp_v4_enum:to_int(type, features_reply);
type_int(#ofp_get_config_request{}) ->
    ofp_v4_enum:to_int(type, get_config_request);
type_int(#ofp_get_config_reply{}) ->
    ofp_v4_enum:to_int(type, get_config_reply);
type_int(#ofp_set_config{}) ->
    ofp_v4_enum:to_int(type, set_config);
type_int(#ofp_packet_in{}) ->
    ofp_v4_enum:to_int(type, packet_in);
type_int(#ofp_flow_removed{}) ->
    ofp_v4_enum:to_int(type, flow_removed);
type_int(#ofp_port_status{}) ->
    ofp_v4_enum:to_int(type, port_status);
type_int(#ofp_barrier_request{}) ->
    ofp_v4_enum:to_int(type, barrier_request);
type_int(#ofp_barrier_reply{}) ->
    ofp_v4_enum:to_int(type, barrier_reply);
type_int(#ofp_queue_get_config_request{}) ->
    ofp_v4_enum:to_int(type, queue_get_config_request);
type_int(#ofp_queue_get_config_reply{}) ->
    ofp_v4_enum:to_int(type, queue_get_config_reply);
type_int(#ofp_role_request{}) ->
    ofp_v4_enum:to_int(type, role_request);
type_int(#ofp_role_reply{}) ->
    ofp_v4_enum:to_int(type, role_reply);
type_int(#ofp_get_async_request{}) ->
    ofp_v4_enum:to_int(type, get_async_request);
type_int(#ofp_get_async_reply{}) ->
    ofp_v4_enum:to_int(type, get_async_reply);
type_int(#ofp_set_async{}) ->
    ofp_v4_enum:to_int(type, set_async);
type_int(#ofp_meter_mod{}) ->
    ofp_v4_enum:to_int(type, meter_mod).


