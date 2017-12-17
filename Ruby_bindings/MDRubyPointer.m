//
//  MDRubyPointer.m
//  Alchemusica
//
//  Created by Toshi Nagata on 08/03/30.
//  Copyright 2008-2017 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "MDObjects.h"

#include "MDRuby.h"

//  Pointer class
VALUE rb_cMRPointer = Qfalse;

#pragma mark ====== Event kind symbols ======

static struct {
	const char *name;
	int kind;
	int code;
	VALUE sym;
} sMREventNameTable[] = {
	{ "null", kMDEventNull, 0, 0 },
	{ "meta", kMDEventMeta, 0, 0 },
	{ "tempo", kMDEventTempo, 0, 0 },
	{ "time_signature", kMDEventTimeSignature, 0, 0 },
	{ "key", kMDEventKey, 0, 0 },
	{ "smpte", kMDEventSMPTE, 0, 0 },
	{ "port", kMDEventPortNumber, 0, 0 },
	{ "text", kMDEventMetaText, 0, 0 },
	{ "copyright", kMDEventMetaText, kMDMetaCopyright, 0 },
	{ "sequence", kMDEventMetaText, kMDMetaSequenceName, 0 },
	{ "instrument", kMDEventMetaText, kMDMetaInstrumentName, 0 },
	{ "lyric", kMDEventMetaText, kMDMetaLyric, 0 },
	{ "marker", kMDEventMetaText, kMDMetaMarker, 0 },
	{ "cue", kMDEventMetaText, kMDMetaCuePoint, 0 },
	{ "progname", kMDEventMetaText, kMDMetaProgramName, 0 },
	{ "devname", kMDEventMetaText, kMDMetaDeviceName, 0 },
	{ "message", kMDEventMetaMessage, 0, 0 },
	{ "program", kMDEventProgram, 0, 0 },
	{ "note", kMDEventNote, 0, 0 },
	{ "control", kMDEventControl, 0, 0 },
	{ "bank_high", kMDEventControl, 0, 0 },
	{ "modulation", kMDEventControl, 1, 0 },
	{ "portament_time", kMDEventControl, 5, 0 },
	{ "data_entry", kMDEventControl, 6, 0 },
	{ "volume", kMDEventControl, 7, 0 },
	{ "pan", kMDEventControl, 10, 0 },
	{ "expression", kMDEventControl, 11, 0 },
	{ "bank_low", kMDEventControl, 32, 0 },
	{ "hold", kMDEventControl, 64, 0 },
	{ "portamento", kMDEventControl, 65, 0 },
	{ "sostenuto", kMDEventControl, 66, 0 },
	{ "soft", kMDEventControl, 67, 0 },
	{ "resonance", kMDEventControl, 71, 0 },
	{ "release", kMDEventControl, 72, 0 },
	{ "attack", kMDEventControl, 73, 0 },
	{ "cutoff", kMDEventControl, 74, 0 },
	{ "portament_cont", kMDEventControl, 84, 0 },
	{ "reverb", kMDEventControl, 91, 0 },
	{ "chorus", kMDEventControl, 93, 0 },
	{ "var_effect", kMDEventControl, 94, 0 },
	{ "data_inc", kMDEventControl, 96, 0 },
	{ "data_dec", kMDEventControl, 97, 0 },
	{ "nrpn_low", kMDEventControl, 98, 0 },
	{ "nrpn_high", kMDEventControl, 99, 0 },
	{ "rpn_low", kMDEventControl, 100, 0 },
	{ "rpn_high", kMDEventControl, 101, 0 },
	{ "all_sounds_off", kMDEventControl, 120, 0 },
	{ "reset_all_controllers", kMDEventControl, 121, 0 },
	{ "all_notes_off", kMDEventControl, 123, 0 },
	{ "omni_off", kMDEventControl, 124, 0 },
	{ "omni_on", kMDEventControl, 125, 0 },
	{ "mono", kMDEventControl, 126, 0 },
	{ "poly", kMDEventControl, 127, 0 },
	{ "pitch_bend", kMDEventPitchBend, 0, 0 },
	{ "channel_pressure", kMDEventChanPres, 0, 0 },
	{ "key_pressure", kMDEventKeyPres, 0, 0 },
	{ "sysex", kMDEventSysex, 0, 0 },
	{ "sysex_cont", kMDEventSysexCont, 0, 0 },
	{ NULL }
};

static VALUE sNoteSymbol;

static const int sMREventNameTableCount = sizeof(sMREventNameTable) / sizeof(sMREventNameTable[0]) - 1;
static BOOL sMREventNameTableInitialized = NO;

static void
s_MREventNameTableInitialize(void)
{
	int i;
	for (i = 0; i < sMREventNameTableCount; i++) {
		sMREventNameTable[i].sym = ID2SYM(rb_intern(sMREventNameTable[i].name));
		if (sMREventNameTable[i].kind == kMDEventNote)
			sNoteSymbol = sMREventNameTable[i].sym;
	}
	sMREventNameTableInitialized = YES;
}

VALUE
MREventSymbolFromEventKindAndCode(int kind, int code, int *is_generic)
{
	int i, j, f = 0;
	if (!sMREventNameTableInitialized)
		s_MREventNameTableInitialize();
	if (kind == kMDEventNote && code >= 0) {
		char notename[6], buf[12];
		code = (unsigned char)code;
		MDEventNoteNumberToNoteName((unsigned char)code, notename);
		snprintf(buf, sizeof buf, "%s(%d)", notename, code);
		if (is_generic != NULL)
			*is_generic = 1;
		return rb_str_new2(buf);
	}
	for (i = 0; i < sMREventNameTableCount; i++) {
		if (kind == sMREventNameTable[i].kind) {
			if ((kind == kMDEventMetaText || kind == kMDEventControl) && code >= 0) {
				for (j = i + 1; j < sMREventNameTableCount; j++) {
					if (sMREventNameTable[j].kind != kind)
						break;
					if (sMREventNameTable[j].code == code) {
						f = 1;
						i = j;
						break;
					}
				}
			}
			if (is_generic != NULL)
				*is_generic = f;
			return sMREventNameTable[i].sym;
		}
	}
	return 0;
}

int
MREventKindAndCodeFromEventSymbol(VALUE sym, int *code, int *is_generic)
{
	int i, c, kind, f = 0;
	int symtype;

	if (!sMREventNameTableInitialized)
		s_MREventNameTableInitialize();
	symtype = TYPE(sym);
	if (FIXNUM_P(sym) || symtype == T_STRING) {
		/*  May be a note event  */
		c = -1;
		if (symtype == T_STRING)
			c = MDEventNoteNameToNoteNumber(StringValuePtr(sym));
		else
			c = FIX2INT(sym);
		if (c >= 0 && c < 128) {
			if (code != NULL)
				*code = c;
			if (is_generic != NULL)
				*is_generic = 0;
			return kMDEventNote;
		}
	}
	
	if (symtype != T_SYMBOL) {
		sym = ID2SYM(rb_intern(StringValuePtr(sym)));
	}
	for (i = 0; i < sMREventNameTableCount; i++) {
		if (sym == sMREventNameTable[i].sym) {
			kind = sMREventNameTable[i].kind;
			c = sMREventNameTable[i].code;
			if (kind == kMDEventMetaText || kind == kMDEventControl) {
				if (c == 0 && sMREventNameTable[i - 1].kind != kind)
					f = 1;
			}
			if (is_generic != NULL)
				*is_generic = f;
			if (code != NULL)
				*code = c;
			return sMREventNameTable[i].kind;
		}
	}
	return -1;
}

#pragma mark ====== Pointer alloc/init/release ======

static MRPointerInfo *
s_MRPointerInfoFromValue(VALUE val)
{
	MRPointerInfo *ip;
	if (rb_obj_is_kind_of(val, rb_cMRPointer)) {
		Data_Get_Struct(val, MRPointerInfo, ip);
		return ip;
	}
	rb_raise(rb_eTypeError, "Cannot get Pointer information from object");
}

static void
s_MRPointer_Release(void *p)
{
	MRPointerInfo *ip = (MRPointerInfo *)p;
	if (ip->pointer != NULL) {
		MDPointerRelease(ip->pointer);
		ip->pointer = NULL;
	}
	[MyDocument unregisterDocumentTrackInfo: &(ip->trackInfo)];
	free(ip);
}

static VALUE
s_MRPointer_Alloc(VALUE klass)
{
	MRPointerInfo *ip = ALLOC(MRPointerInfo);
	memset(ip, 0, sizeof(MRPointerInfo));
	[MyDocument registerDocumentTrackInfo: &(ip->trackInfo)];
	return Data_Wrap_Struct(klass, 0, s_MRPointer_Release, ip);
}

void
s_MRPointer_InitWithTrackInfo(VALUE val, MDTrack *track, MyDocument *doc, int num, int position)
{
	MRPointerInfo *ip;
	Data_Get_Struct(val, MRPointerInfo, ip);
	ip->trackInfo.doc = doc;
	ip->trackInfo.track = track;
	if (num < 0 && doc != nil)
		ip->trackInfo.num = [[doc myMIDISequence] lookUpTrack: track];
	else ip->trackInfo.num = num;
	ip->pointer = MDPointerNew(track);
	if (position >= 0)
		MDPointerSetPosition(ip->pointer, position);
}

/*
 *  call-seq:
 *     Pointer.new
 *     Pointer.new(doc, n)
 *     Pointer.new(track)
 *
 *  Creates a new Pointer object.
 */
static VALUE
s_MRPointer_Initialize(int argc, VALUE *argv, VALUE self)
{
	VALUE val1, val2, val3;
	MyDocument *doc = nil;
	MDTrack *track;
	int num = -1, position = -1;
	rb_scan_args(argc, argv, "03", &val1, &val2, &val3);
	if (NIL_P(val1)) {
		track = MDTrackNew();
	} else if (rb_obj_is_kind_of(val1, rb_cMRTrack)) {
		MyDocumentTrackInfo *trackInfoPtr = TrackInfoFromMRTrackValue(val1);
		doc = trackInfoPtr->doc;
		track = trackInfoPtr->track;
		num = trackInfoPtr->num;
		val3 = val2;
	} else if (rb_obj_is_kind_of(val1, rb_cMRSequence)) {
		doc = MyDocumentFromMRSequenceValue(val1);
		num = NUM2INT(rb_Integer(val2));
		if (num < 0 || num >= [[doc myMIDISequence] trackCount])
			rb_raise(rb_eRangeError, "track count (%d) out of range", num);
		track = [[doc myMIDISequence] getTrackAtIndex: num];  // Not retained
	} else {
		rb_raise(rb_eTypeError, "invalid argument; the first argument must be either Sequence or Track");
	}
	if (val3 != Qnil)
		position = NUM2INT(rb_Integer(val3));
	s_MRPointer_InitWithTrackInfo(self, track, doc, num, position);
	return Qnil;
}

static VALUE
s_MRPointer_InitializeCopy(VALUE self, VALUE val)
{
	MRPointerInfo *ip, *ip2;
	Data_Get_Struct(self, MRPointerInfo, ip);
	if (!rb_obj_is_kind_of(val, rb_cMRPointer))
		rb_raise(rb_eTypeError, "Pointer instance is expected");
	Data_Get_Struct(val, MRPointerInfo, ip2);
	ip->trackInfo = ip2->trackInfo;
	ip->pointer = MDPointerNew(ip->trackInfo.track);
	if (ip->pointer == NULL)
		rb_raise(rb_eNoMemError, "out of memory while duplicating an Pointer object");
	MDPointerCopy(ip->pointer, ip2->pointer);
	return self;
}

MDPointer *
MDPointerFromMRPointerValue(VALUE val)
{
	MRPointerInfo *ip;
	if (rb_obj_is_kind_of(val, rb_cMRPointer)) {
		Data_Get_Struct(val, MRPointerInfo, ip);
		if (ip->pointer != NULL)
			return ip->pointer;
	}
	rb_raise(rb_eTypeError, "Cannot get MDPointer from object");
}

VALUE
MRPointerValueFromTrackInfo(MDTrack *track, MyDocument *doc, int num, int position)
{
	VALUE val = s_MRPointer_Alloc(rb_cMRPointer);
	s_MRPointer_InitWithTrackInfo(val, track, doc, num, position);
	return val;
}

#pragma mark ====== Ruby methods ======

/*
 *  call-seq:
 *     pointer.position=(n)
 *     pointer.moveto(n)
 *
 *  Set the current position. The method "moveto" returns true if the resulting pointer 
 *  points to an event, otherwise returns false. The method "position=" always returns
 *  'n'; this is the feature of Ruby.
 */
static VALUE
s_MRPointer_SetPosition(VALUE self, VALUE val)
{
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	int position = NUM2INT(val);
	if (MDPointerSetPosition(pt, position))
		return Qtrue;
	else return Qfalse;
}

/*
 *  call-seq:
 *     pointer.position
 *     pointer.position(n)
 *
 *  No argument: get the current position. With argument: set the current position;
 *  returns true if the resulting pointer points to an event, otherwise returns false.
 */
static VALUE
s_MRPointer_Position(int argc, VALUE *argv, VALUE self)
{
	VALUE val;
	int position;
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	rb_scan_args(argc, argv, "01", &val);
	if (val == Qnil) {		
		position = MDPointerGetPosition(pt);
		return INT2NUM(position);
	} else {
		return s_MRPointer_SetPosition(self, val);
	}
}

/*
 *  call-seq:
 *     pointer.moveby(n)
 *
 *  Move the pointer by n. Returns true if the resulting pointer points to an event, 
 *  otherwise returns false.
 */
static VALUE
s_MRPointer_MoveBy(VALUE self, VALUE val)
{
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	int n = NUM2INT(val);
	if (MDPointerSetRelativePosition(pt, n))
		return Qtrue;
	else return Qfalse;
}

/*
 *  call-seq:
 *     pointer.track
 *
 *  Get the parent track as an Track object.
 */
static VALUE
s_MRPointer_Track(VALUE self)
{
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MyDocumentTrackInfo *tip = &ip->trackInfo;
	return MRTrackValueFromTrackInfo(tip->track, tip->doc, tip->num);
}

/*
 *  call-seq:
 *     pointer.top
 *
 *  Move to the top of the track.
 */
VALUE
MRPointer_Top(VALUE self)
{
	return s_MRPointer_SetPosition(self, INT2NUM(-1));
}

/*
 *  call-seq:
 *     pointer.bottom
 *
 *  Move to the bottom of the track.
 */
VALUE
MRPointer_Bottom(VALUE self)
{
	return s_MRPointer_SetPosition(self, INT2NUM(0x3fffffff));
}

/*
 *  call-seq:
 *     pointer.next
 *
 *  Move forward. If the pointer goes over the end of track, returns false;
 *  otherwise returns true.
 */
VALUE
MRPointer_Next(VALUE self)
{
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	if (MDPointerForward(pt) == NULL) {
		return Qfalse;
	} else return Qtrue;
}

/*
 *  call-seq:
 *     pointer.last
 *
 *  Move backward. If the pointer goes over the beginning of track, returns false;
 *  otherwise returns true.
 */
VALUE
MRPointer_Last(VALUE self)
{
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	if (MDPointerBackward(pt) == NULL) {
		return Qfalse;
	} else return Qtrue;
}

/*
 *  call-seq:
 *     pointer.next_in_selection
 *
 *  Move forward within the selection. If no more event is present within selection, the pointer
 *  is set to the end of track and returns false; otherwise returns true.
 */
VALUE
MRPointer_NextInSelection(VALUE self)
{
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	IntGroup *pset = [[ip->trackInfo.doc selectionOfTrack: ip->trackInfo.num] pointSet];
	if (MDPointerForwardWithPointSet(pt, pset, NULL) == NULL) {
		return Qfalse;
	} else return Qtrue;
}

/*
 *  call-seq:
 *     pointer.last_in_selection
 *
 *  Move backward within the selection. If no more event is present within selection, the pointer
 *  is set to the top of track and returns false; otherwise returns true.
 */
VALUE
MRPointer_LastInSelection(VALUE self)
{
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	IntGroup *pset = [[ip->trackInfo.doc selectionOfTrack: ip->trackInfo.num] pointSet];
	if (MDPointerBackwardWithPointSet(pt, pset, NULL) == NULL) {
		return Qfalse;
	} else return Qtrue;
}

/*
 *  call-seq:
 *     pointer.jump_to_tick(tick)
 *
 *  Move to the first event having the tick not smaller than the given value.
 *  If such an event does not exist, the pointer is moved to the bottom and
 *  returns false. Otherwise returns true.
 */
static VALUE
s_MRPointer_JumpToTick(VALUE self, VALUE val)
{
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDTickType tick = (MDTickType)floor(NUM2DBL(val) + 0.5);
	if (MDPointerJumpToTick(pt, tick))
		return Qtrue;
	else return Qfalse;
}

static void
s_MRPointer_OutOfBoundsError(MDPointer *pt)
{
	static const char *msg = "the pointer points outside the track";
	if (pt != NULL)
		rb_raise(rb_eStandardError, "%s (position = %d)", msg, (int)MDPointerGetPosition(pt));
	else
		rb_raise(rb_eStandardError, "%s", msg); 
}

static void
s_MRPointer_BadKindError(MDPointer *pt)
{
	char buf[64];
	MDEvent *ep;
	if (pt != NULL && (ep = MDPointerCurrent(pt)) != NULL)
		MDEventToKindString(ep, buf, sizeof buf);
	else buf[0] = 0;
	rb_raise(rb_eStandardError, "event kind (%s) not suitable for this operation", buf);
}

/*
 *  call-seq:
 *     pointer.kind
 *
 *  Returns the "kind" of the event. Returns one of the following symbols:
 *  :null, :meta, :tempo, :time_signature, :key, :smpte, :port, :text, :message, 
 *  :program, :note, :control, :pitch_bend, :channel_pressure, :key_pressure, 
 *  :sysex, :sysex_cont
 */
static VALUE
s_MRPointer_Kind(VALUE self)
{
	int kind;
/*	int code; */
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
/*	code = MDGetCode(ep); */
	return MREventSymbolFromEventKindAndCode(kind, -1, NULL); /* returns the generic symbol */
}

/*
 *  call-seq:
 *     pointer.kind=(symbol)
 *
 *  Set the "kind" of the event. The kind must be one of the symbols listed in 
 *  pointer.kind().
 */
static VALUE
s_MRPointer_SetKind(VALUE self, VALUE val)
{
	int kind, code;
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
    MDEvent event;
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MREventKindAndCodeFromEventSymbol(val, &code, NULL);
	if (kind < 0)
		rb_raise(rb_eArgError, "the value to set must be a symbol (:meta, :tempo, etc.)");
	if (kind == MDGetKind(ep) && (code == MDGetCode(ep) || (kind != kMDEventMetaText && kind != kMDEventControl)))
		return val; // No operation
    MDEventClear(&event);
    MDEventDefault(&event, kind);
    if (code != 0)
        MDSetCode(&event, code);
    MDSetTick(&event, MDGetTick(ep));
    if (kind == kMDEventMetaText && ep->kind == kMDEventMetaText) {
        MDCopyMessage(&event, ep);
    } else if (kind == kMDEventControl && ep->kind == kMDEventControl) {
        MDSetData1(&event, MDGetData1(ep));
    }
	if (ip->trackInfo.doc != nil) {
		MDEventObject *newEvent = [[[MDEventObject alloc] init] autorelease];
        MDEventMove(&newEvent->event, &event, 1);
		newEvent->position = MDPointerGetPosition(pt);
		[ip->trackInfo.doc replaceEvent: newEvent inTrack: ip->trackInfo.num];
	} else {
        MDEventClear(ep);
        MDEventMove(ep, &event, 1);
	}
	return val;
}

/*
 *  call-seq:
 *     pointer.code
 *
 *  Returns the code of the event. Only meaningful for the following event kind:
 *  :meta, :text, :message, :note, :control, :key_pressure. Otherwise, nil is returned.
 */
static VALUE
s_MRPointer_Code(VALUE self)
{
	int kind, code;
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventMeta && kind != kMDEventMetaText && kind != kMDEventMetaMessage && kind != kMDEventNote && kind != kMDEventControl && kind != kMDEventKeyPres)
		return Qnil;
	code = MDGetCode(ep);
	return INT2NUM(code);
}

/*
 *  call-seq:
 *     pointer.code=(val)
 *
 *  Set the code of the event. Only meaningful for the following event kind:
 *  :meta, :text, :message, :note, :control, :key_pressure. The value must be
 *  0..127.
 */
static VALUE
s_MRPointer_SetCode(VALUE self, VALUE val)
{
	int kind, code;
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventMeta && kind != kMDEventMetaText && kind != kMDEventMetaMessage && kind != kMDEventNote && kind != kMDEventControl && kind != kMDEventKeyPres)
		s_MRPointer_BadKindError(pt);
	code = NUM2INT(val);
//	if (code < 0 || code >= 128)
//		rb_raise(rb_eRangeError, "the code value (%d) must be 0..127", code);
	if (code < 0)
		code = 0;
	else if (code >= 128)
		code = 127;
	if (ip->trackInfo.doc != nil) {
		MDEventFieldData ed;
		ed.ucValue[0] = kind;
		ed.ucValue[1] = code;
		[ip->trackInfo.doc changeValue: ed.whole ofType: kMDEventFieldKindAndCode atPosition: MDPointerGetPosition(pt) inTrack: ip->trackInfo.num];
	} else {
		MDSetCode(ep, code);
	}
	return val;
}

/*
 *  call-seq:
 *     pointer.control_kind
 *
 *  If the event is a control event, then returns the symbol representing the
 *  event.code. Otherwise, returns nil.
 */
static VALUE
s_MRPointer_ControlKind(VALUE self)
{
    int kind;
    int code;
    MDPointer *pt = MDPointerFromMRPointerValue(self);
    MDEvent *ep = MDPointerCurrent(pt);
    if (ep == NULL)
        s_MRPointer_OutOfBoundsError(pt);
    kind = MDGetKind(ep);
    code = MDGetCode(ep);
    if (kind == kMDEventControl)
        return MREventSymbolFromEventKindAndCode(kind, code, NULL);
    else return Qnil;
}

/*
 *  call-seq:
 *     pointer.text_kind
 *
 *  If the event is a text meta event, then returns the symbol representing the
 *  event.code. Otherwise, returns nil.
 */
static VALUE
s_MRPointer_TextKind(VALUE self)
{
    int kind;
    int code;
    MDPointer *pt = MDPointerFromMRPointerValue(self);
    MDEvent *ep = MDPointerCurrent(pt);
    if (ep == NULL)
        s_MRPointer_OutOfBoundsError(pt);
    kind = MDGetKind(ep);
    code = MDGetCode(ep);
    if (kind == kMDEventMetaText)
        return MREventSymbolFromEventKindAndCode(kind, code, NULL);
    else return Qnil;
}

VALUE
MRPointer_GetDataSub(const MDEvent *ep)
{
	int kind;
	VALUE vals[5];
	kind = MDGetKind(ep);
	switch (kind) {
		case kMDEventProgram:
		case kMDEventPitchBend:
		case kMDEventControl:
		case kMDEventChanPres:
		case kMDEventKeyPres:
		case kMDEventPortNumber:
			return INT2NUM(MDGetData1(ep));
		case kMDEventTempo:
			return rb_float_new(MDGetTempo(ep));
		case kMDEventMetaText:
		case kMDEventMetaMessage:
		case kMDEventSysex:
		case kMDEventSysexCont: {
			int32_t messageLength;
            int32_t i;
			const char *cp = (const char *)MDGetMessageConstPtr(ep, &messageLength);
			if (kind == kMDEventSysex || kind == kMDEventSysexCont) {
				vals[0] = rb_ary_new2(messageLength);
				for (i = 0; i < messageLength; i++) {
					rb_ary_store(vals[0], i, INT2FIX((unsigned char)cp[i]));
				}
				return vals[0];
			} else {
                if (kind == kMDEventMetaText) {
                    /*  Chop at the first null byte  */
                    for (i = 0; i < messageLength; i++) {
                        if (cp[i] == 0)
                            break;
                    }
                    messageLength = i;
                }
				return rb_str_new(cp, messageLength);
			}
		}
		case kMDEventSMPTE: {
			const MDSMPTERecord *rp = MDGetSMPTERecordPtr(ep);
			vals[0] = INT2NUM(rp->hour);
			vals[1] = INT2NUM(rp->min);
			vals[2] = INT2NUM(rp->sec);
			vals[3] = INT2NUM(rp->frame);
			vals[4] = INT2NUM(rp->subframe);
			return rb_ary_new4(5, vals);
		}
		case kMDEventTimeSignature: {
			const unsigned char *cup = MDGetMetaDataPtr(ep);
			vals[0] = INT2NUM(cup[0]);
			vals[1] = INT2NUM(1 << cup[1]);
			vals[2] = INT2NUM(cup[1]);
			vals[3] = INT2NUM(cup[2]);
			return rb_ary_new4(4, vals);
		}
		case kMDEventKey: {
			char buf[16];
			const char *cp = (const char *)MDGetMetaDataPtr(ep);
			MDEventToDataString(ep, buf, sizeof buf);
			vals[0] = rb_str_new2(buf);
			vals[1] = INT2NUM(cp[0]);
			vals[2] = INT2NUM(cp[1] & 1);
			return rb_ary_new4(3, vals);
		}
		default:
			return Qnil;
	}
}

/*
 *  call-seq:
 *     pointer.data
 *
 *  Returns the data of the event. Only meaningful for the following event kind:
 *  :port, :program, :pitch_bend, :control, :channel_pressure, :key_pressure => integer
 *  :text, :message, :sysex, :sysex_cont => string
 *  :tempo => float
 *  :time_signature, :smpte => array of integers
 *  :key => [string, number of key accidentals, major(1) or minor(0)]
 *  Otherwise, nil is returned.
 */
static VALUE
s_MRPointer_Data(VALUE self)
{
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	return MRPointer_GetDataSub(ep);
}

void
MRPointer_SetDataSub(VALUE val, MDEvent *ep, MyDocument *doc, int trackNo, int32_t position)
{
	int kind, data, mode;
	MDEventFieldData ed;
	kind = MDGetKind(ep);	
	switch (kind) {
		case kMDEventMetaText:
		case kMDEventMetaMessage:
		case kMDEventSysex:
		case kMDEventSysexCont: {
			int32_t messageLength;
			const unsigned char *cp;
			StringValue(val);
			cp = (const unsigned char *)RSTRING_PTR(val);
			messageLength = (int)RSTRING_LEN(val);
			if (doc != nil) {
				[doc changeMessage: [NSData dataWithBytes: cp length: messageLength] atPosition: position inTrack: trackNo];
			} else {
				MDSetMessageLength(ep, messageLength);
				MDSetMessage(ep, cp);
			}
			return;
		}		
		case kMDEventPitchBend:
			data = NUM2INT(val);
			if (data < -8192)
				data = -8192;
			else if (data >= 8192)
				data = 8191;
			ed.intValue = data;
			mode = kMDEventFieldData;
			break;
		case kMDEventPortNumber:
		case kMDEventProgram:
		case kMDEventControl:
		case kMDEventChanPres:
		case kMDEventKeyPres:
			data = NUM2INT(val);
			if (data < 0)
				data = 0;
			else if (data >= 128)
				data = 127;
			ed.intValue = data;
			mode = kMDEventFieldData;
			break;
		case kMDEventTempo:
			ed.floatValue = (float)NUM2DBL(val);
			mode = kMDEventFieldTempo;
			break;
		case kMDEventSMPTE:
			ed.smpte.hour = NUM2INT(Ruby_ObjectAtIndex(val, 0));
			ed.smpte.min = NUM2INT(Ruby_ObjectAtIndex(val, 1));
			ed.smpte.sec = NUM2INT(Ruby_ObjectAtIndex(val, 2));
			ed.smpte.frame = NUM2INT(Ruby_ObjectAtIndex(val, 3));
			ed.smpte.subframe = NUM2INT(Ruby_ObjectAtIndex(val, 4));
			mode = kMDEventFieldSMPTE;
			break;
		case kMDEventTimeSignature: {
			unsigned int ui;
			VALUE valn;
			ed.ucValue[0] = NUM2INT(Ruby_ObjectAtIndex(val, 0));
			ui = NUM2INT(Ruby_ObjectAtIndex(val, 1));
			ed.ucValue[1] = 0;
			while ((ui >>= 1) != 0)
				ed.ucValue[1]++;
			if ((valn = Ruby_ObjectAtIndex(val, 2)) != Qnil)
				ed.ucValue[2] = NUM2INT(valn);
			else ed.ucValue[2] = 24;
			if ((valn = Ruby_ObjectAtIndex(val, 3)) != Qnil)
				ed.ucValue[3] = NUM2INT(valn);
			else ed.ucValue[3] = 8;
			mode = kMDEventFieldMetaData;
			break;
		}
		case kMDEventKey: {
			VALUE vals[3];
			if (TYPE(val) == T_ARRAY) {
				vals[0] = (RARRAY_PTR(val))[0];
				vals[1] = (RARRAY_PTR(val))[1];
				vals[2] = (RARRAY_PTR(val))[2];
			} else if (TYPE(val) == T_STRING) {
				vals[0] = val;
				vals[1] = Qnil;
				vals[2] = Qnil;
			} else if (FIXNUM_P(val)) {
				vals[0] = Qnil;
				vals[1] = val;
				vals[2] = Qnil;
			} else {
				vals[0] = rb_funcall(val, rb_intern("inspect"), 0);
				rb_raise(rb_eTypeError, "Bad argument for key signature: %s", StringValuePtr(vals[0]));
			}
			if (TYPE(vals[0]) == T_STRING) {
				char *p = StringValuePtr(vals[0]);
				int n = MDEventDataStringToEvent(ep, p, &ed);
				if (n != kMDEventFieldMetaData)
					rb_raise(rb_eTypeError, "the string '%s' is not a valid key signature representation", p);
			} else {
				int n1 = NUM2INT(vals[1]);
				if (n1 < -7 || n1 > 7)
					rb_raise(rb_eRangeError, "the number of accidentals (%d) is out of bounds", n1);
				ed.ucValue[0] = n1;
				ed.ucValue[1] = (NUM2INT(vals[2]) & 1);
			}
			mode = kMDEventFieldMetaData;
			break;
		}
		default:
			rb_raise(rb_eStandardError, "invalid type for setting data");
			break;
	}
	
	if (doc != nil) {
		[doc changeValue: ed.whole ofType: mode atPosition: position inTrack: trackNo];
	} else {
		switch (mode) {
			case kMDEventFieldData:
				MDSetData1(ep, ed.intValue);
				break;
			case kMDEventFieldSMPTE:
				*(MDGetSMPTERecordPtr(ep)) = ed.smpte;
				break;
			case kMDEventFieldMetaData:
				memmove(MDGetMetaDataPtr(ep), ed.ucValue, 4);
				break;
			case kMDEventFieldTempo:
				MDSetTempo(ep, ed.floatValue);
				break;
		}
	}
}

/*
 *  call-seq:
 *     pointer.data=(val)
 *
 *  Set the code of the event. Only meaningful for the following event kind:
 *  :program, :pitch_bend, :control, :channel_pressure, :key_pressure <= integer;
 *    The value must be -8192..8191 for pitch bend, 0..127 for others.
 *  :text, :message, :sysex, :sysex_cont <= string
 *  :tempo <= float
 *  :time_signature, :smpte <= array of integers
 *  :key <= string or integer (number of key accidentals) or [string, integer, integer]
 */
static VALUE
s_MRPointer_SetData(VALUE self, VALUE val)
{
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	MRPointer_SetDataSub(val, ep, ip->trackInfo.doc, ip->trackInfo.num, MDPointerGetPosition(pt));
	return val;
}

/*
 *  call-seq:
 *     pointer.duration
 *
 *  Returns the duration of the event. Only meaningful for the note event.
 *  Otherwise, nil is returned.
 */
static VALUE
s_MRPointer_Duration(VALUE self)
{
	int kind, du;
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventNote)
		return Qnil;
	du = MDGetDuration(ep);
	return INT2NUM(du);
}

/*
 *  call-seq:
 *     pointer.duration=(val)
 *
 *  Set the duration of the event. Only meaningful for the note event.
 */
static VALUE
s_MRPointer_SetDuration(VALUE self, VALUE val)
{
	int kind, du;
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventNote)
		s_MRPointer_BadKindError(pt);
	du = NUM2INT(rb_Integer(val));
	if (du < 1)
		rb_raise(rb_eRangeError, "the duration value (%d) must be a positive integer", du);
	if (ip->trackInfo.doc != nil) {
		[ip->trackInfo.doc changeDuration: du atPosition: MDPointerGetPosition(pt) inTrack: ip->trackInfo.num];
	} else {
		MDPointerSetDuration(pt, du);
	}
	return val;
}

/*
 *  call-seq:
 *     pointer.velocity
 *
 *  Returns the note-on velocity of the event. Only meaningful for the note event.
 *  Otherwise, nil is returned.
 */
static VALUE
s_MRPointer_Velocity(VALUE self)
{
	int kind, vel;
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventNote)
		return Qnil;
	vel = MDGetNoteOnVelocity(ep);
	return INT2NUM(vel);
}

/*
 *  call-seq:
 *     pointer.velocity=(val)
 *
 *  Set the note-on velocity of the event. Only meaningful for the note event.
 *  The value must be 1..127.
 */
static VALUE
s_MRPointer_SetVelocity(VALUE self, VALUE val)
{
	int kind, vel;
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventNote)
		s_MRPointer_BadKindError(pt);
	vel = NUM2INT(val);
	if (vel < 1 || vel >= 128)
		rb_raise(rb_eRangeError, "the velocity value (%d) must be 1..127", vel);
	if (ip->trackInfo.doc != nil) {
		MDEventFieldData ed;
		ed.ucValue[0] = vel;
		ed.ucValue[1] = MDGetNoteOffVelocity(ep);
		[ip->trackInfo.doc changeValue: ed.whole ofType: kMDEventFieldVelocities atPosition: MDPointerGetPosition(pt) inTrack: ip->trackInfo.num];
	} else {
		MDSetNoteOnVelocity(ep, vel);
	}
	return val;
}

/*
 *  call-seq:
 *     pointer.release_velocity
 *
 *  Returns the note-off velocity of the event. Only meaningful for the note event.
 *  Otherwise, nil is returned.
 */
static VALUE
s_MRPointer_ReleaseVelocity(VALUE self)
{
	int kind, vel;
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventNote)
		return Qnil;
	vel = MDGetNoteOffVelocity(ep);
	return INT2NUM(vel);
}

/*
 *  call-seq:
 *     pointer.release_velocity=(val)
 *
 *  Set the note-on velocity of the event. Only meaningful for the note event.
 *  The value must be 0..127.
 */
static VALUE
s_MRPointer_SetReleaseVelocity(VALUE self, VALUE val)
{
	int kind, vel;
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	kind = MDGetKind(ep);
	if (kind != kMDEventNote)
		s_MRPointer_BadKindError(pt);
	vel = NUM2INT(val);
	if (vel < 1 || vel >= 128)
		rb_raise(rb_eRangeError, "the velocity value (%d) must be 1..127", vel);
	if (ip->trackInfo.doc != nil) {
		MDEventFieldData ed;
		ed.ucValue[0] = MDGetNoteOnVelocity(ep);
		ed.ucValue[1] = vel;
		[ip->trackInfo.doc changeValue: ed.whole ofType: kMDEventFieldVelocities atPosition: MDPointerGetPosition(pt) inTrack: ip->trackInfo.num];
	} else {
		MDSetNoteOffVelocity(ep, vel);
	}
	return val;
}

/*
 *  call-seq:
 *     pointer.tick
 *
 *  Returns the tick of the event.
 */
static VALUE
s_MRPointer_Tick(VALUE self)
{
	MDTickType tick;
	MDPointer *pt = MDPointerFromMRPointerValue(self);
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	tick = MDGetTick(ep);
	return INT2NUM(tick);
}

/*
 *  call-seq:
 *     pointer.tick=(val)
 *
 *  Set the tick of the event. This may cause a change in event order, but it
 *  will only happen when the cached modification events are sent to MyDocument
 *  (see the comment in s_MRPointerScheduleEventModification)
 */
static VALUE
s_MRPointer_SetTick(VALUE self, VALUE val)
{
	MDTickType tick;
	MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	MDPointer *pt = ip->pointer;
	MDEvent *ep = MDPointerCurrent(pt);
	if (ep == NULL)
		s_MRPointer_OutOfBoundsError(pt);
	tick = (MDTickType)NUM2DBL(val);
	if (ip->trackInfo.doc != nil) {
		[ip->trackInfo.doc changeTick: tick atPosition: MDPointerGetPosition(pt) inTrack: ip->trackInfo.num originalPosition: kMDNegativeTick];
	} else {
		MDPointerChangeTick(pt, tick, -1);
	}
	return val;
}

/*
 *  call-seq:
 *     pointer.selected?
 *
 *  Returns whether the event is selected.
 */
static VALUE
s_MRPointer_SelectedP(VALUE self)
{
	const MRPointerInfo *ip = s_MRPointerInfoFromValue(self);
	if (ip != NULL && ip->trackInfo.doc != NULL) {
		BOOL flag = [ip->trackInfo.doc isSelectedAtPosition: MDPointerGetPosition(ip->pointer) inTrack: ip->trackInfo.num];
		return (flag ? Qtrue : Qfalse);
	}
	return Qfalse;
}

#pragma mark ====== Initialize class ======

void
MRPointerInitClass(void)
{
	if (rb_cMRPointer != Qfalse)
		return;

	rb_cMRPointer = rb_define_class("Pointer", rb_cObject);
	rb_define_alloc_func(rb_cMRPointer, s_MRPointer_Alloc);
	rb_define_private_method(rb_cMRPointer, "initialize", s_MRPointer_Initialize, -1);
	rb_define_private_method(rb_cMRPointer, "initialize_copy", s_MRPointer_InitializeCopy, 1);
	rb_define_method(rb_cMRPointer, "position", s_MRPointer_Position, -1);
	rb_define_method(rb_cMRPointer, "position=", s_MRPointer_SetPosition, 1);
	rb_define_method(rb_cMRPointer, "move_to", s_MRPointer_SetPosition, 1);
	rb_define_method(rb_cMRPointer, "move_by", s_MRPointer_MoveBy, 1);
	rb_define_method(rb_cMRPointer, "track", s_MRPointer_Track, 0);
	rb_define_method(rb_cMRPointer, "top", MRPointer_Top, 0);
	rb_define_method(rb_cMRPointer, "bottom", MRPointer_Bottom, 0);
	rb_define_method(rb_cMRPointer, "next", MRPointer_Next, 0);
	rb_define_method(rb_cMRPointer, "last", MRPointer_Last, 0);
	rb_define_method(rb_cMRPointer, "next_in_selection", MRPointer_NextInSelection, 0);
	rb_define_method(rb_cMRPointer, "last_in_selection", MRPointer_LastInSelection, 0);
	rb_define_method(rb_cMRPointer, "jump_to_tick", s_MRPointer_JumpToTick, 1);
	rb_define_method(rb_cMRPointer, "kind", s_MRPointer_Kind, 0);
	rb_define_method(rb_cMRPointer, "kind=", s_MRPointer_SetKind, 1);
	rb_define_method(rb_cMRPointer, "code", s_MRPointer_Code, 0);
	rb_define_method(rb_cMRPointer, "code=", s_MRPointer_SetCode, 1);
    rb_define_method(rb_cMRPointer, "control_kind", s_MRPointer_ControlKind, 0);
    rb_define_method(rb_cMRPointer, "text_kind", s_MRPointer_TextKind, 0);
	rb_define_method(rb_cMRPointer, "data", s_MRPointer_Data, 0);
	rb_define_method(rb_cMRPointer, "data=", s_MRPointer_SetData, 1);
	rb_define_method(rb_cMRPointer, "tick", s_MRPointer_Tick, 0);
	rb_define_method(rb_cMRPointer, "tick=", s_MRPointer_SetTick, 1);
	rb_define_method(rb_cMRPointer, "duration", s_MRPointer_Duration, 0);
	rb_define_method(rb_cMRPointer, "duration=", s_MRPointer_SetDuration, 1);
	rb_define_method(rb_cMRPointer, "velocity", s_MRPointer_Velocity, 0);
	rb_define_method(rb_cMRPointer, "velocity=", s_MRPointer_SetVelocity, 1);
	rb_define_method(rb_cMRPointer, "release_velocity", s_MRPointer_ReleaseVelocity, 0);
	rb_define_method(rb_cMRPointer, "release_velocity=", s_MRPointer_SetReleaseVelocity, 1);
	rb_define_method(rb_cMRPointer, "selected?", s_MRPointer_SelectedP, 0);
}
