-module(amf3).
-export([read_object/1]).

-include("action_message.hrl").

-define(undefined_marker, 16#00).
-define(null_marker,      16#01).
-define(false_marker,     16#02).
-define(true_marker,      16#03).
-define(integer_marker,   16#04).
-define(double_marker,    16#05).
-define(string_marker,    16#06).
-define(xml_doc_marker,   16#07).
-define(date_marker,      16#08).
-define(array_marker,     16#09).
-define(object_marker,    16#0A).
-define(xml_marker,       16#0B).


%% The high bit of the first 3 bytes are used as flags to determine 
%% whether the next byte is part of the integer. 
%% With up to 3 bits of the 32 bits being used as flags, 
%% only 29 significant bits remain for encoding an integer. 
%% This means the largest unsigned integer value that can be represented is 2^29 - 1.
%%          (hex)          :          (binary)
%% 0x00000000 - 0x0000007F : 0xxxxxxx
%% 0x00000080 - 0x00003FFF : 1xxxxxxx 0xxxxxxx
%% 0x00004000 - 0x001FFFFF : 1xxxxxxx 1xxxxxxx 0xxxxxxx
%% 0x00200000 - 0x3FFFFFFF : 1xxxxxxx 1xxxxxxx 1xxxxxxx xxxxxxxx
%% 0x40000000 - 0xFFFFFFFF : throw range exception
%% return {ok, Value, RemainBin} or {bad, Reason}
read_uint_29(<<2#0:1, First:7, Rest/binary>>) ->
    {ok, First, Rest};
read_uint_29(<<2#1:1, First:7, 2#0:1, Second:7, Rest/binary>>) ->    
    {ok, ((First bor 16#80) bsl 8) bor Second, Rest};
read_uint_29(<<2#1:1, First:7, 2#1:1, Second:7, 2#0:1, Third:7, Rest/binary>>) ->
    {ok, ((First bor 16#80) bsl 16) bor ((Second bor 16#80) bsl 8) bor Third, Rest};
read_uint_29(<<2#1:1, First:7, 2#1:1, Second:7, 2#1:1, Third:7, Forth:8, Rest/binary>>) ->
    {ok, ((First bor 16#80) bsl 24) bor ((Second bor 16#80) bsl 16) bor ((Third bor 16#80) bsl 8) bor Forth, Rest};
read_uint_29(_) ->
    {bad, "Not a binary or number out of range or empty binary"}.

%% Read object from ETS based on the key Ref
%% Return {ok, Obj} or {bad, Reason}
read_object_reference(Ref) ->
    {bad, {"Not yet implemented: read_object_reference", Ref}}.

%% Read object from ETS based on the key Ref
%% Return {ok, Obj} or {bad, Reason}
read_trait_reference(Ref) ->
    {bad, {"Not yet implemented: read_trait_reference", Ref}}.

%% Read object from ETS based on the key Ref
%% Return {ok, Str} or {bad, Reason}
read_string_reference(Ref) ->
    {bad, {"Not yet implemented: read_string_reference", Ref}}.

write_object_reference(Ref, Obj) ->
    %% TODO store the {Ref, Obj} to ETS
    {ok, Ref, Obj}.

%% Not store if string is empty
write_string_reference(Ref, Str) when length(Str) == 0 ->
    {ok, Ref, Str};
%% Return {ok, Ref, Str}
write_string_reference(Ref, Str) ->
    %% TODO store the {Ref, Str} to ETS
    {ok, Ref, Str}.
    
%% AMF 0 and AMF 3 use (non-modified) UTF-8 to encode strings. UTF-8
%% is the abbreviation for 8-bit Unicode Transformation Format. UTF-8
%% strings are typically preceded with a byte-length header followed
%% by a sequence of variable length (1 to 4 octets) encoded Unicode
%% code-points. AMF 3 uses a slightly modified byte-length header; a
%% detailed description is provided below and referred to throughout
%% the document.
%%          (hex)          :          (binary) 
%% 0x00000000 - 0x0000007F : 0xxxxxxx
%% 0x00000080 - 0x000007FF : 110xxxxx 10xxxxxx 
%% 0x00000800 - 0x0000FFFF : 1110xxxx 10xxxxxx 10xxxxxx 
%% 0x00010000 - 0x0010FFFF : 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
decode_to_utf8(<<>>, Acc) -> {ok, Acc};
decode_to_utf8(<<2#0:1, First:7, Rest/binary>>, Acc) -> 
    decode_to_utf8(Rest, Acc ++ [First]);
decode_to_utf8(<<2#110:3, First:5, 2#10:2, Second:6, Rest/binary>>, Acc) ->
    Char = (First bsl 6) bor Second,
    decode_to_utf8(Rest, Acc ++ [Char]);
decode_to_utf8(<<2#1110:4, First:4, 2#10:2, Second:6, 2#10:2, Third:6, Rest/binary>>, Acc) ->
    Char = (First bsl 12) bor (Second bsl 6) bor Third,
    decode_to_utf8(Rest, Acc ++ [Char]);
decode_to_utf8(<<2#11110:5, First:3, 2#10:2, Second:6, 2#10:2, Third:6, 2#10:2, Forth:6,Rest/binary>>, Acc) ->
    Char = (First bsl 18) bor (Second bsl 12) bor (Third bsl 6) bor Forth,
    decode_to_utf8(Rest, Acc ++ [Char]).
    
binary_to_utf8(Bin) ->
    decode_to_utf8(Bin, []).


%% return {ok, StrValue, Rest} or {bad, Reason}
read_string(Bin) ->
    {ok, Ref, BinAfterRef} = read_uint_29(Bin),
    RefIndex = Ref bsr 1,
    case Ref band 1 of
	0 ->
	    {ok, Str} = read_string_reference(RefIndex),
	    {ok, Str, BinAfterRef};
	_ ->
	    StrLen = RefIndex,
	    {StrBin, BinAfterStrBin} = split_binary(BinAfterRef, StrLen),	    
	    {ok, Str} = binary_to_utf8(StrBin),
	    %% io:fwrite("StrLen: ~p~nBinString: ~n~p~nString: ~p~n", [StrLen, StrBin, Str]),
	    {ok, _, _} = write_string_reference(RefIndex, Str),
	    {ok, Str, BinAfterStrBin}
    end.

read_properties(Bin, Count, Total, Acc) when Count == Total ->
    {ok, Acc, Bin};
read_properties(Bin, Count, Total, Acc) ->
    {ok, PropertyName, Rest} = read_string(Bin),
    read_properties(Rest, Count + 1, Total, Acc ++ [PropertyName]).

%% return {ok, Trait, Rest} or {bad, Reason}
read_trait(Ref, Bin) ->
    case Ref band 3 of
	1 ->
    	    {ok, ObjRef} = read_trait_reference(Ref bsr 2),
	    {ok, ObjRef, Bin};
	_ ->
	    Externalizable = (Ref band 4) == 4,
	    Dynamic = (Ref band 8) == 8,
	    PropertyCount = Ref bsr 4,
	    {ok, ClassName, BinAfterClassName} = read_string(Bin),
	    {ok, Properties, BinAfterProperties} = read_properties(BinAfterClassName, 0, PropertyCount, []),
	    Trait = #trait{className = ClassName, externalizable = Externalizable, dynamic = Dynamic, properties = Properties},
	    {ok, Trait, BinAfterProperties}
    end.

%% return {ok, [Value1, Value2, ...], Rest} or {bad, Reason}
read_dense_array(Bin, Count, Total, Acc) when Count == Total ->
    {ok, Acc, Bin};
read_dense_array(Bin, Count, Total, Acc) ->
    {ok, Value, BinAfterValue} = read_object(Bin),
    read_dense_array(BinAfterValue, Count + 1, Total, Acc ++ [Value]).

%% return {ok, [{Key,Value}], Rest} or {bad, Reason}
read_associative_array_ext(Bin, Count, Total, Acc) when Count == Total ->
    {ok, Acc, Bin};
read_associative_array_ext(Bin, Count, Total, Acc) ->
    Key = integer_to_list(Count),
    {ok, Value, BinAfterValue} = read_object(Bin),
    read_dense_array(BinAfterValue, Count + 1, Total, Acc ++ [{Key, Value}]).

%% return {ok, [{Key,Value}], Rest} or {bad, Reason}
read_associative_array(Bin, Acc) ->
    {ok, Key, BinAfterKey} = read_string(Bin),
    if 
	length(Key) == 0 ->
	    {ok, Acc, BinAfterKey};
	true ->
	    {ok, Value, BinAfterValue} = read_object(BinAfterKey),
	    read_associative_array(BinAfterValue, Acc ++ [{Key, Value}])
    end.

%% Return {ok, Map=[{Key, Value}, ...], Rest} 
%% or {ok, Array=[Value1, Value2, ...], Rest}
%% or {bad, Reason}
read_array(Bin) ->
    {ok, Ref, BinAfterRef} = read_uint_29(Bin),
    IndexRef = Ref bsr 1,
    case Ref band 1 of
	0 ->
	    {ok, ObjRef} = read_object_reference(IndexRef),
	    {ok, ObjRef, BinAfterRef};
	_ ->
	    Len = IndexRef,
	    {ok, Map, BinAfterMap} = read_associative_array(BinAfterRef, []),
	    if 
		length(Map) == 0 ->
		    %% Read as normal array [Value1, Value2, ...]
		    {ok, Array, BinAfterArray} = read_dense_array(BinAfterMap, 0, Len, []),
		    {ok, _, _} = write_object_reference(IndexRef, Array),
		    {ok, Array, BinAfterArray};
		true ->
		    %% Continue read as associative arrray
		    {ok, MapExt, BinAfterMapExt} = read_associative_array_ext(BinAfterMap, 0, Len, Map),
		    {ok, _, _} = write_object_reference(IndexRef, MapExt),
		    {ok, MapExt, BinAfterMapExt}
	    end
    end.

%% Return {ok, value|Value, Rest} or {bad, Reason}
read_object(<<?undefined_marker:8, Rest/binary>>) -> {bad, {"Undefined marker ", Rest}};
read_object(<<?null_marker:8,      Rest/binary>>)  -> {ok, null, Rest};
read_object(<<?false_marker:8,     Rest/binary>>)  -> {ok, false, Rest};
read_object(<<?true_marker:8,      Rest/binary>>)  -> {ok, true, Rest};
read_object(<<?integer_marker:8,   Rest/binary>>)  -> read_uint_29(Rest);
read_object(<<?double_marker:8,    Rest/binary>>) -> {bad, {"Not yet implemented marker", Rest}};
read_object(<<?string_marker:8,    Rest/binary>>) -> {bad, {"Not yet implemented marker", Rest}};
read_object(<<?xml_doc_marker:8,   Rest/binary>>) -> {bad, {"Not yet implemented marker", Rest}};
read_object(<<?date_marker:8,      Rest/binary>>) -> {bad, {"Not yet implemented marker", Rest}};
read_object(<<?array_marker:8,     Rest/binary>>) -> read_array(Rest);
read_object(<<?object_marker:8,    Rest/binary>>)  ->
    {ok, Ref, BinAfterRef} = read_uint_29(Rest),
    case Ref band 1 of
	0 ->
	    {ok, ObjRef} = read_object_reference(Ref bsr 1),
	    {ok, ObjRef, BinAfterRef};
	_ ->
	    {ok, TraitObj, _BinAfterTrait} = read_trait(Ref, BinAfterRef),
	    io:fwrite("Trait: ~p~n", [TraitObj]),
	    {bad, "To be continued..."}	    
    end;
read_object(<<?xml_marker:8,       Rest/binary>>) -> {bad, {"Not yet implemented marker", Rest}};

read_object(<<>>) ->
    {ok, null, <<>>};

read_object(Something) ->
    {bad, {"Not a binary or not matched any marker", Something}}.