//
//  MDRubyTrack.m
//  Alchemusica
//
//  Created by Toshi Nagata on 08/03/27.
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
#import "MDRubyPointer.h"

#include "MDRuby.h"

//  Track class
VALUE rb_cMRTrack = Qfalse;

static void
s_MRTrack_Release(void *p)
{
	MyDocumentTrackInfo *ip = (MyDocumentTrackInfo *)p;
	if (ip->track != NULL) {
		MDTrackRelease(ip->track);
		ip->track = NULL;
	}
	[MyDocument unregisterDocumentTrackInfo: ip];
	free(ip);
}

static VALUE
s_MRTrack_Alloc(VALUE klass)
{
	MyDocumentTrackInfo *ip = ALLOC(MyDocumentTrackInfo);
	memset(ip, 0, sizeof(MyDocumentTrackInfo));
	[MyDocument registerDocumentTrackInfo: ip];
	return Data_Wrap_Struct(klass, 0, s_MRTrack_Release, ip);
}

/*
 *  call-seq:
 *     Track.new
 *     Track.new(doc, n)
 *
 *  Returns a new Track object.
 */
static VALUE
s_MRTrack_Initialize(int argc, VALUE *argv, VALUE self)
{
	VALUE val1, val2;
	MyDocumentTrackInfo *ip;
	Data_Get_Struct(self, MyDocumentTrackInfo, ip);
	rb_scan_args(argc, argv, "02", &val1, &val2);
	if (NIL_P(val1)) {
		ip->track = MDTrackNew();
	} else if (rb_obj_is_kind_of(val1, rb_cMRTrack)) {
		MyDocumentTrackInfo *ip2 = TrackInfoFromMRTrackValue(val1);
		*ip = *ip2;
		MDTrackRetain(ip->track);
	} else if (rb_obj_is_kind_of(val1, rb_cMRSequence)) {
		MyDocument *doc = MyDocumentFromMRSequenceValue(val1);
		int n = NUM2INT(val2);
		if (n < 0 || n >= [[doc myMIDISequence] trackCount])
			rb_raise(rb_eRangeError, "track count (%d) out of range", n);
		ip->track = [[doc myMIDISequence] getTrackAtIndex: n];
		MDTrackRetain(ip->track);
		ip->doc = doc;
		ip->num = n;
	} else {
		rb_raise(rb_eTypeError, "invalid argument; the first argument must be either Sequence or Track");
	}
	return Qnil;
}

MDTrack *
MDTrackFromMRTrackValue(VALUE val)
{
	MyDocumentTrackInfo *ip;
	if (rb_obj_is_kind_of(val, rb_cMRTrack)) {
		Data_Get_Struct(val, MyDocumentTrackInfo, ip);
		if (ip->track != NULL)
			return ip->track;
	}
	rb_raise(rb_eTypeError, "Cannot get MDTrack pointer from object");
}

MyDocumentTrackInfo *
TrackInfoFromMRTrackValue(VALUE val)
{
	MyDocumentTrackInfo *ip;
	if (rb_obj_is_kind_of(val, rb_cMRTrack)) {
		Data_Get_Struct(val, MyDocumentTrackInfo, ip);
		return ip;
	}
	rb_raise(rb_eTypeError, "Cannot get track information from object");
}

VALUE
MRTrackValueFromTrackInfo(MDTrack *track, void *myDocument, int num)
{
	MyDocumentTrackInfo *ip;
	MyDocument *doc = (MyDocument *)myDocument;
	VALUE val = s_MRTrack_Alloc(rb_cMRTrack);
	Data_Get_Struct(val, MyDocumentTrackInfo, ip);
	ip->doc = doc;
	if (num < 0 && doc != nil)
		ip->num = [[doc myMIDISequence] lookUpTrack: track];
	else ip->num = num;
	ip->track = track;
	MDTrackRetain(ip->track);
	return val;
}

#pragma mark ====== Ruby methods ======

/*
 *  call-seq:
 *     track.index
 *
 *  Index of the track in the parent Sequence. If the track is not
 *  associated with any Sequence, returns nil.
 */
static VALUE
s_MRTrack_Index(VALUE self)
{
	MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip->doc == nil)
		return Qnil;
	else return FIX2INT(ip->num);
}

/*
 *  call-seq:
 *     track.duration
 *
 *  Get the duration of the track in tick.
 */
static VALUE
s_MRTrack_Duration(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	MDTickType duration = MDTrackGetDuration(track);
	return INT2NUM(duration);
}

/*
 *  call-seq:
 *     track.duration=
 *
 *  Set the duration of the track in tick.
 */
static VALUE
s_MRTrack_SetDuration(VALUE self, VALUE val)
{
	MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	MDTickType duration = (MDTickType)floor(NUM2DBL(val) + 0.5);
	MDTickType largestTick = MDTrackGetLargestTick(ip->track);
	if (duration <= largestTick)
		rb_raise(rb_eRangeError, "duration value (%d) out of limit, must be >= %d", (int)duration, (int)largestTick + 1);
	if (ip->doc != nil) {
		[ip->doc changeTrackDuration: duration ofTrack: ip->num];
	} else {
		MDTrackSetDuration(ip->track, duration);
	}
	return val;
}

/*
 *  call-seq:
 *     track.count
 *     track.nevents
 *
 *  Get the number of events in the track.
 */
static VALUE
s_MRTrack_Count(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	int count = MDTrackGetNumberOfEvents(track);
	return INT2NUM(count);
}

/*
 *  call-seq:
 *     track.count_midi
 *     track.nmidievents
 *
 *  Get the number of MIDI events in the track.
 */
static VALUE
s_MRTrack_CountMIDI(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	int count = MDTrackGetNumberOfChannelEvents(track, -1);
	return INT2NUM(count);
}

/*
 *  call-seq:
 *     track.count_sysex
 *     track.nsysexevents
 *
 *  Get the number of sysex events in the track.
 */
static VALUE
s_MRTrack_CountSysex(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	int count = MDTrackGetNumberOfSysexEvents(track);
	return INT2NUM(count);
}

/*
 *  call-seq:
 *     track.count_meta
 *     track.nmetaevents
 *
 *  Get the number of meta events in the track.
 */
static VALUE
s_MRTrack_CountMeta(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	int count = MDTrackGetNumberOfNonMIDIEvents(track);
	return INT2NUM(count);
}

/*
 *  call-seq:
 *     track.pointer(n)
 *     track.event(n)
 *
 *  Create a new Pointer object pointing to the n-th event in this track.
 *  (n is zero based, but -1 is also allowed)
 */
static VALUE
s_MRTrack_Pointer(VALUE self, VALUE nval)
{
	MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	int pos;
	if (nval == Qnil)
		pos = -1;
	else pos = NUM2INT(rb_Integer(nval));
	return MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, pos);
}

/*
 *  call-seq:
 *     track.channel
 *
 *  Get the MIDI output channel of the track.
 */
static VALUE
s_MRTrack_Channel(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	int ch = MDTrackGetTrackChannel(track);
	return INT2NUM(ch);
}

/*
 *  call-seq:
 *     track.channel=
 *
 *  Set the MIDI output channel of the track.
 */
static VALUE
s_MRTrack_SetChannel(VALUE self, VALUE val)
{
	MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	int ch = NUM2INT(val);
	if (ch <= 0 || ch > 16)
		rb_raise(rb_eRangeError, "MIDI channel (%d) must be between 1 and 16", ch);
	if (ip->doc != nil) {
		[ip->doc changeTrackChannel: ch forTrack: ip->num];
	} else {
		MDTrackSetTrackChannel(ip->track, ch);
	}
	return val;
}

/*
 *  call-seq:
 *     track.device
 *
 *  Get the MIDI output device of the track.
 */
static VALUE
s_MRTrack_Device(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	char name[256];
	MDTrackGetDeviceName(track, name, sizeof name);
	return rb_str_new2(name);
}

/*
 *  call-seq:
 *     track.device=
 *
 *  Set the MIDI output device of the track.
 */
static VALUE
s_MRTrack_SetDevice(VALUE self, VALUE val)
{
	char name[256];
	MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	char *p = StringValuePtr(val);
	strncpy(name, p, 255);
	name[255] = 0;
	if (ip->doc != nil) {
		[ip->doc changeDevice: [NSString stringWithUTF8String: name] forTrack: ip->num];
	} else {
		MDTrackSetDeviceName(ip->track, name);
	}
	return val;
}

/*
 *  call-seq:
 *     track.name
 *
 *  Get the name of the track.
 */
static VALUE
s_MRTrack_Name(VALUE self)
{
	MDTrack *track = MDTrackFromMRTrackValue(self);
	char name[256];
	MDTrackGetName(track, name, sizeof name);
	return rb_str_new2(name);
}

/*
 *  call-seq:
 *     track.name=
 *
 *  Set the name of the track.
 */
static VALUE
s_MRTrack_SetName(VALUE self, VALUE val)
{
	char name[256];
	MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	char *p = StringValuePtr(val);
	strncpy(name, p, 255);
	name[255] = 0;
	if (ip->doc != nil) {
		[ip->doc changeTrackName: [NSString stringWithUTF8String: name] forTrack: ip->num];
	} else {
		MDTrackSetName(ip->track, name);
	}
	return val;
}

/*
 *  call-seq:
 *     track.selection -> MREventSet
 *
 *  Get the selection of the track.
 */
static VALUE
s_MRTrack_Selection(VALUE self)
{
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip != NULL && ip->doc != nil) {
		MDSelectionObject *sel = [ip->doc selectionOfTrack: ip->num];
		if (sel != nil)
			return MREventSetValueFromIntGroupAndTrackInfo([sel pointSet], ip->track, ip->doc, sel->isEndOfTrackSelected);
		else return Qnil;
	}
	rb_raise(rb_eTypeError, "selection cannot be defined for non-document tracks");
	return Qnil; /* not reached */
}

/*
 *  call-seq:
 *     track.selection=(pointset)
 *
 *  Set the selection of the track.
 */
static VALUE
s_MRTrack_SetSelection(VALUE self, VALUE sval)
{
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip != NULL && ip->doc != nil) {	
		MDSelectionObject *sel;
		if (sval == Qnil)
			sel = [[MDSelectionObject alloc] init];
		else
			sel = [[MDSelectionObject alloc] initWithMDPointSet: IntGroupFromValue(sval)];
		if (rb_obj_is_kind_of(sval, rb_cMREventSet) && RTEST(MREventSet_EOTSelected(sval)))
			sel->isEndOfTrackSelected = YES;
		[ip->doc setSelection: sel inTrack: ip->num sender: nil];
		[sel autorelease];
	} else {
		rb_raise(rb_eTypeError, "selection cannot be defined for non-document tracks");
	}
	return sval;
}

/*
 *  call-seq:
 *     track.eventset(*args, &block) -> eventset
 *
 *  Create a new eventset associated to this track. The arguments are the same
 *  as in MRPointSet.new.
 */
static VALUE
s_MRTrack_EventSet(int argc, VALUE *argv, VALUE self)
{
	IntGroup *pset;
	VALUE val, rval;
	int32_t max, n;

	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip == NULL || ip->track == NULL)
		rb_raise(rb_eStandardError, "Internal error: track not defined");

	n = MDTrackGetNumberOfEvents(ip->track);

	/*  Create a MREventSet object  */
	/*  (without the accompanying block)  */
	if (argc == 0) {
		/*  The default set is (0...nevents)  */
		rval = rb_range_new(INT2NUM(0), INT2NUM(n), 1);
		argc = 1;
		argv = &rval;
	}
	
	val = rb_funcall2(rb_cMREventSet, rb_intern("new"), argc, argv);
	
	/*  Limit by the number of actual events  */
	pset = IntGroupFromValue(val);
	max = IntGroupMaximum(pset);
	if (n <= max)
		IntGroupRemove(pset, n, max - n + 1);
	
	if (rb_block_given_p()) {
		VALUE pval;
		MRPointerInfo *pvalinfo;
		IntGroup *ps_to_remove = IntGroupNew();
		int32_t i;
		pval = s_MRTrack_Pointer(self, Qnil);
		Data_Get_Struct(pval, MRPointerInfo, pvalinfo);
		for (i = 0; (n = IntGroupGetNthPoint(pset, i)) >= 0; i++) {
			MDPointerSetPosition(pvalinfo->pointer, n);
			if (!RTEST(rb_yield(pval)))
				IntGroupAdd(ps_to_remove, n, 1);
		}
		IntGroupRemoveIntGroup(pset, ps_to_remove);
		IntGroupRelease(ps_to_remove);
	}
	
	/*  Set track  */
	MREventSet_SetTrack(val, self);

	return val;
}

/*
 *  call-seq:
 *     track.all_events -> eventset
 *
 *  Create a new eventset containing all events in this track.
 */
static VALUE
s_MRTrack_AllEvents(VALUE self)
{
	IntGroup *pset;
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip == NULL || ip->track == NULL)
		rb_raise(rb_eStandardError, "Internal error: track not defined");
	pset = IntGroupNew();
	IntGroupAdd(pset, 0, MDTrackGetNumberOfEvents(ip->track));
	return MREventSetValueFromIntGroupAndTrackInfo(pset, ip->track, ip->doc, 1);
}

/*
 *  call-seq:
 *     track.selected?
 *
 *  Return whether the track is selected (in the track list of the graphic window)
 */
static VALUE
s_MRTrack_SelectedP(VALUE self)
{
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip != NULL && ip->doc != nil)
		return ([ip->doc isTrackSelected: ip->num] ? Qtrue : Qfalse);
	else return Qfalse;
}

/*
 *  call-seq:
 *     track.editable?
 *
 *  Return whether the track is editable
 */
static VALUE
s_MRTrack_EditableP(VALUE self)
{
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	if (ip != NULL && ip->doc != nil) {
		MDTrackAttribute attr = [ip->doc trackAttributeForTrack: ip->num];
		if (attr & kMDTrackAttributeEditable)
			return Qtrue;
	}
	return Qfalse;
}

/*
 *  call-seq:
 *     track.each block
 *
 *  Execute the block for each event; the block argument is a Pointer object.
 */
static VALUE
s_MRTrack_Each(VALUE self)
{
	VALUE pval = s_MRTrack_Pointer(self, Qnil);
	while (MRPointer_Next(pval) != Qfalse)
		rb_yield(pval);
	return self;
}

/*
 *  call-seq:
 *     track.each_selected block
 *
 *  Execute the block for each event in selection; the block argument is a Pointer object.
 */
static VALUE
s_MRTrack_EachSelected(VALUE self)
{
	VALUE pval = s_MRTrack_Pointer(self, Qnil);
	while (MRPointer_NextInSelection(pval) != Qfalse)
		rb_yield(pval);
	return self;
}

static VALUE
s_call_block_with_MRPointer(VALUE yarg, VALUE oarg, int argc, VALUE *argv)
{
	int pos = NUM2INT(rb_Integer(yarg));
	MDPointer *pt = MDPointerFromMRPointerValue(oarg);
	MDPointerSetPosition(pt, pos);
	return rb_yield(oarg);
}

/*
 *  call-seq:
 *     track.each_in(enumerable) block
 *
 *  Execute the block for each event pointed by the enumerable.
 *  The block argument is a Pointer object.
 */
static VALUE
s_MRTrack_EachIn(VALUE self, VALUE enval)
{
	VALUE pval = s_MRTrack_Pointer(self, Qnil);
	rb_block_call(enval, rb_intern("each"), 0, NULL, s_call_block_with_MRPointer, pval);
//	MRPointer_Flush(pval);
	return self;
}

/*
 *  call-seq:
 *     track.reverse_each block
 *
 *  Execute the block for each event with reverse order; the block argument is a Pointer object.
 */
static VALUE
s_MRTrack_ReverseEach(VALUE self)
{
	VALUE pval = s_MRTrack_Pointer(self, Qnil);
	MRPointer_Bottom(pval);
	while (MRPointer_Last(pval) != Qfalse)
		rb_yield(pval);
	return self;
}

/*
 *  call-seq:
 *     track.reverse_each_selected block
 *
 *  Execute the block for each event in selection; the block argument is a Pointer object.
 */
static VALUE
s_MRTrack_ReverseEachSelected(VALUE self)
{
	VALUE pval = s_MRTrack_Pointer(self, Qnil);
	MRPointer_Bottom(pval);
	while (MRPointer_LastInSelection(pval) != Qfalse)
		rb_yield(pval);
	return self;
}

/*
 *  call-seq:
 *     track.reverse_each_in(enumerable) block
 *
 *  Execute the block for each event pointed by the enumerable in reverse order.
 *  The block argument is a Pointer object.
 */
static VALUE
s_MRTrack_ReverseEachIn(VALUE self, VALUE enval)
{
	VALUE pval = s_MRTrack_Pointer(self, Qnil);
	rb_block_call(enval, rb_intern("reverse_each"), 0, NULL, s_call_block_with_MRPointer, pval);
//	MRPointer_Flush(pval);
	return self;
}

/*
 *  call-seq:
 *     track.merge(trackarg[, pointset])
 *
 *  Merge the events in trackarg, at positions in (optionally given) pointset.
 */
static VALUE
s_MRTrack_Merge(int argc, VALUE *argv, VALUE self)
{
	VALUE tval, pval, rval;
	IntGroup *pset, *pset2;
	MDTrack *tr;
	int success;
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	rb_scan_args(argc, argv, "11", &tval, &pval);
	if (pval != Qnil)
		pset = IntGroupFromValue(pval);
	else
		pset = NULL;
	tr = MDTrackFromMRTrackValue(tval);
	if (tr == NULL)
		rb_raise(rb_eArgError, "track is not given");
	if (ip->doc != nil) {
		IntGroupObject *psobj = (pset == NULL ? nil : [[[IntGroupObject alloc] initWithMDPointSet: pset] autorelease]);
		MDTrackObject *trobj = [[[MDTrackObject alloc] initWithMDTrack: tr] autorelease];
		success = [ip->doc insertMultipleEvents: trobj at: psobj toTrack: ip->num selectInsertedEvents: NO insertedPositions: &pset2];
	} else {
		success = (MDTrackMerge(ip->track, tr, &pset) == 0);
		pset2 = pset;
	}
	if (!success) {
		/*  pset2 is undefined  */
		rb_raise(rb_eStandardError, "cannot merge events");
	}
	rval = ValueFromIntGroup(pset2);
	IntGroupRelease(pset2);
	return rval;
}

/*
 *  call-seq:
 *     track.copy(pointset) -> new_track
 *
 *  Copy the events at pointset and create a new track from them.
 */
static VALUE
s_MRTrack_Copy(VALUE self, VALUE sval)
{
	IntGroup *pset;
	MDTrack *track;
	VALUE rval;
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	pset = IntGroupFromValue(sval);
	if (MDTrackExtract(ip->track, &track, pset) != 0)
		rb_raise(rb_eStandardError, "cannot copy events");
	rval = MRTrackValueFromTrackInfo(track, nil, -1);
	MDTrackRelease(track);
	return rval;	
}

/*
 *  call-seq:
 *     track.cut(pointset) -> new_track
 *
 *  Cut the events at pointset and create a new track from them.
 */
static VALUE
s_MRTrack_Cut(VALUE self, VALUE sval)
{
	IntGroup *pset;
	MDTrack *track;
	VALUE rval;
	int success;
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	pset = IntGroupFromValue(sval);
	if (ip->doc != nil) {
		IntGroupObject *psobj = [[[IntGroupObject alloc] initWithMDPointSet: pset] autorelease];
		success = [ip->doc deleteMultipleEventsAt: psobj fromTrack: ip->num deletedEvents: &track];
	} else {
		success = (MDTrackUnmerge(ip->track, &track, pset) != 0);
	}
	if (!success)
		rb_raise(rb_eStandardError, "cannot cut events");
	rval = MRTrackValueFromTrackInfo(track, nil, -1);
	MDTrackRelease(track);
	return rval;	
}

static void
s_raise_if_missing_parameter(int argc, int expect_argc, const char *msg)
{
	if (argc < expect_argc) {
		if (expect_argc == 1)
			rb_raise(rb_eArgError, "parameter (%s) is required", msg);
		else
			rb_raise(rb_eArgError, "at least %d parameters (%s) are required", expect_argc, msg);
	}
}

/*
 *  call-seq:
 *     track.add(tick, type, data,...) -> self
 *     track << [tick, type, data,...] -> self
 *
 *  Create a new midi event. Type is an integer or a note-number string for note events,
 *  and a symbol for other events.
 *  Data is/are specified for each type of event as follows:
 *    note            duration, velocity[, release-velocity]
 *    :tempo          tempo (Float)
 *    :time_signature numerator, denominator[, 3rd-byte, 4th-byte] (as defined in SMF)
 *    :key            key (-7 to 7), :major/:minor/0/1
 *    :smpte          hr, min, sec, frame, frac_frame
 *    :port           port_number
 *    :text           code, String
 *    :copyright, :sequence, :instrument, :lyric, :marker, :cue, :progname, :devname String
 *    :meta           code, String or Array
 *    :sysex          String or Array
 *    :program        program_no
 *    :control        control_no, value (0..127)
 *    :bank_high, :modulation, etc.  value (0..127)
 *    :pitch_bend     value (-8192..8191)
 *    :channel_pressure value
 *    :key_pressure   note_on (Integer) or note_name (String), value
 */
static VALUE
s_MRTrack_Add(VALUE self, VALUE sval)
{
	VALUE *argv, val;
	int argc, kind, code, is_generic;
	int n1, n2, n3;
	MDTickType tick;
	MDEventObject *eobj;
	MDEvent *ep;
	unsigned char *ucp;
	MDSMPTERecord *smp;
	char *p;
	const MyDocumentTrackInfo *ip = TrackInfoFromMRTrackValue(self);
	sval = rb_ary_to_ary(sval);
	argc = (int)RARRAY_LEN(sval);
	argv = RARRAY_PTR(sval);
	if (argc < 2)
		rb_raise(rb_eArgError, "at least 2 parameters should be present");
	tick = NUM2INT(rb_Integer(argv[0]));
	if (tick < 0)
		rb_raise(rb_eArgError, "the tick value must be non-negative");
	kind = MREventKindAndCodeFromEventSymbol(argv[1], &code, &is_generic);
	if (kind < 0) {
		volatile VALUE v = rb_inspect(argv[1]);
		rb_raise(rb_eArgError, "unknown event type: %s", StringValuePtr(v));
	}
	eobj = [[[MDEventObject alloc] init] autorelease];
	ep = [eobj eventPtr];
	MDSetTick(ep, tick);
	MDSetKind(ep, kind);
	argc -= 2;
	argv += 2;
	switch (kind) {
		case kMDEventNote:
			if (is_generic) {
				s_raise_if_missing_parameter(argc, 3, "note number, duration, velocity");
				if (FIXNUM_P(argv[0]))
					code = FIX2INT(argv[0]);
				else
					code = MDEventNoteNameToNoteNumber(StringValuePtr(argv[0]));
				if (code < 0 || code >= 128)
					rb_raise(rb_eArgError, "note number (%d) out of range", code);
				argc--;
				argv++;
			} else s_raise_if_missing_parameter(argc, 2, "duration, velocity");
			MDSetCode(ep, code);
			n1 = NUM2INT(rb_Integer(argv[0]));
			n2 = NUM2INT(rb_Integer(argv[1]));
			if (n1 <= 0)
				rb_raise(rb_eArgError, "note duration (%d) must be positive", n1);
			if (n2 <= 0 || n2 >= 128)
				rb_raise(rb_eArgError, "note velocity (%d) is out of range", n2);
			MDSetDuration(ep, n1);
			MDSetNoteOnVelocity(ep, n2);
			if (argc > 2) {
				n1 = NUM2INT(rb_Integer(argv[2]));
				if (n1 < 0 || n1 >= 128)
					rb_raise(rb_eArgError, "release velocity (%d) is out of range", n1);
				MDSetNoteOffVelocity(ep, n1);
			}
			break;
		case kMDEventTempo:
			s_raise_if_missing_parameter(argc, 1, "tempo");
			MDSetTempo(ep, (float)NUM2DBL(rb_Float(argv[0])));
			break;
		case kMDEventTimeSignature:
			s_raise_if_missing_parameter(argc, 2, "n/m");
			ucp = MDGetMetaDataPtr(ep);
			ucp[0] = NUM2INT(rb_Integer(argv[0]));
			ucp[1] = NUM2INT(rb_Integer(argv[1]));
			if (argc > 2)
				ucp[2] = NUM2INT(rb_Integer(argv[2]));
			if (argc > 3)
				ucp[3] = NUM2INT(rb_Integer(argv[3]));
			break;
		case kMDEventKey:
			s_raise_if_missing_parameter(argc, 2, "number of accidentals, major/minor");
			ucp = MDGetMetaDataPtr(ep);
			ucp[0] = NUM2INT(rb_Integer(argv[0]));
			if (ucp[0] + 7 > 14)
				rb_raise(rb_eArgError, "number of accidentals (%d) is out of range", (int)(signed char)ucp[0]);
			if ((n1 = TYPE(argv[1])) == T_STRING || n1 == T_SYMBOL) {
				p = StringValuePtr(argv[1]);
				if (strcasecmp(p, "major") == 0)
					ucp[1] = 0;
				else if (strcasecmp(p, "minor") == 0)
					ucp[1] = 1;
				else
					rb_raise(rb_eArgError, "unknown word '%s' for key specification", p);
			} else ucp[1] = (0 != NUM2INT(rb_Integer(argv[1])));
			break;
		case kMDEventSMPTE:
			s_raise_if_missing_parameter(argc, 5, "hour, min, sec, frame, subframe");
			smp = MDGetSMPTERecordPtr(ep);
			smp->hour = NUM2INT(rb_Integer(argv[0]));
			smp->min = NUM2INT(rb_Integer(argv[1]));
			smp->sec = NUM2INT(rb_Integer(argv[2]));
			smp->frame = NUM2INT(rb_Integer(argv[3]));
			smp->subframe = NUM2INT(rb_Integer(argv[4]));
			break;
		case kMDEventPortNumber:
			s_raise_if_missing_parameter(argc, 1, "port number");
			MDSetData1(ep, NUM2INT(rb_Integer(argv[0])));
			break;
		case kMDEventMetaText:
			if (is_generic) {
				s_raise_if_missing_parameter(argc, 2, "text kind number (0-15), string");
				code = NUM2INT(rb_Integer(argv[0]));
				argc--;
				argv++;
			} else s_raise_if_missing_parameter(argc, 1, "string");
			if (code < 0 || code > 15)
				rb_raise(rb_eArgError, "text kind number (%d) is out of range", code);
			MDSetCode(ep, code);
			StringValue(argv[0]);
			MDSetMessageLength(ep, (int)RSTRING_LEN(argv[0]));
			MDSetMessage(ep, (unsigned char *)(RSTRING_PTR(argv[0])));
			break;
		case kMDEventMetaMessage:
		case kMDEventSysex:
		case kMDEventSysexCont:
			if (kind == kMDEventMetaMessage) {
				s_raise_if_missing_parameter(argc, 2, "code, string or array of integers");
				code = NUM2INT(rb_Integer(argv[0]));
				if (code < 16 || code > 127)
					rb_raise(rb_eArgError, "meta code (%d) is out of range", code);
				MDSetCode(ep, code);
				argc--;
				argv++;
			} else {
				s_raise_if_missing_parameter(argc, 1, "string or array of integers");
			}
			if ((n1 = TYPE(argv[0])) == T_STRING) {
				n2 = (int)RSTRING_LEN(argv[0]);
				ucp = (unsigned char *)(RSTRING_PTR(argv[0]));
			} else {
				val = rb_ary_to_ary(argv[0]);
				n2 = (int)RARRAY_LEN(val);
				ucp = (unsigned char *)malloc(n2);
				for (n3 = 0; n3 < n2; n3++)
					ucp[n3] = NUM2INT(rb_Integer(RARRAY_PTR(val)[n3]));
			}
			if (n2 > 0) {
				if (kind == kMDEventSysex || kind == kMDEventSysexCont) {
					if (kind == kMDEventSysex) {
						if (ucp[0] != 0xf0)
							rb_raise(rb_eArgError, "sysex must start with 0xf0");
						n3 = 1;
					} else n3 = 0;
					for ( ; n3 < n2; n3++) {
						if (ucp[n3] >= 128 && (n3 != n2 - 1 || ucp[n3] != 0xf7))
							rb_raise(rb_eArgError, "sysex must not contain numbers >= 128");
					}
				}
			}
			MDSetMessageLength(ep, n2);
			MDSetMessage(ep, ucp);
			if (n1 != T_STRING)
				free(ucp);
			break;
		case kMDEventProgram:
			s_raise_if_missing_parameter(argc, 1, "program number");
			n1 = NUM2INT(rb_Integer(argv[0]));
			if (n1 < 0 || n1 >= 128)
				rb_raise(rb_eArgError, "program number (%d) is out of range", n1);
			MDSetData1(ep, n1);
			break;
		case kMDEventControl:
			if (is_generic) {
				s_raise_if_missing_parameter(argc, 2, "control number, value");
				code = NUM2INT(rb_Integer(argv[0]));
				argc--;
				argv++;
			} else s_raise_if_missing_parameter(argc, 1, "control value");
			if (code < 0 || code >= 128)
				rb_raise(rb_eArgError, "control code (%d) is out of range", code);
			n1 = NUM2INT(rb_Integer(argv[0]));
			if (n1 < 0 || n1 >= 128)
				rb_raise(rb_eArgError, "control value (%d) is out of range", n1);
			MDSetCode(ep, code);
			MDSetData1(ep, n1);
			break;
		case kMDEventPitchBend:
			s_raise_if_missing_parameter(argc, 1, "pitch bend");
			n1 = NUM2INT(rb_Integer(argv[0]));
			if (n1 < -8192 || n1 >= 8192)
				rb_raise(rb_eArgError, "pitch bend value (%d) is out of range", n1);
			MDSetData1(ep, n1);
			break;
		case kMDEventChanPres:
			s_raise_if_missing_parameter(argc, 1, "channel pressure");
			n1 = NUM2INT(rb_Integer(argv[0]));
			if (n1 < 0 || n1 >= 128)
				rb_raise(rb_eArgError, "channel pressure value (%d) is out of range", n1);
			MDSetData1(ep, n1);
			break;
		case kMDEventKeyPres:
			s_raise_if_missing_parameter(argc, 2, "note number, key pressure");
			if (FIXNUM_P(argv[0]))
				code = FIX2INT(argv[0]);
			else
				code = MDEventNoteNameToNoteNumber(StringValuePtr(argv[0]));
			if (code < 0 || code >= 128)
				rb_raise(rb_eArgError, "note number (%d) out of range", code);
			n1 = NUM2INT(rb_Integer(argv[1]));
			if (n1 < 0 || n1 >= 128)
				rb_raise(rb_eArgError, "key pressure value (%d) is out of range", n1);
			MDSetCode(ep, code);
			MDSetData1(ep, n1);
			break;
		default:
			rb_raise(rb_eArgError, "internal error? unknown event kind (%d)", kind);
	}
	
	/*  Insert the new event to the track  */
	if (ip->doc != nil) {
		[ip->doc insertEvent: eobj toTrack: ip->num];
	} else {
		MDPointer *pt = MDPointerNew(ip->track);
		MDPointerInsertAnEvent(pt, ep);
		MDPointerRelease(pt);
	}
	
	return self;
}

#pragma mark ====== Initialize class ======

void
MRTrackInitClass(void)
{
	if (rb_cMRTrack != Qfalse)
		return;

	rb_cMRTrack = rb_define_class("Track", rb_cObject);
	rb_define_alloc_func(rb_cMRTrack, s_MRTrack_Alloc);
	rb_define_private_method(rb_cMRTrack, "initialize", s_MRTrack_Initialize, -1);
	rb_define_method(rb_cMRTrack, "index", s_MRTrack_Index, 0);
	rb_define_method(rb_cMRTrack, "duration", s_MRTrack_Duration, 0);
	rb_define_method(rb_cMRTrack, "duration=", s_MRTrack_SetDuration, 1);
	rb_define_method(rb_cMRTrack, "count", s_MRTrack_Count, 0);
	rb_define_method(rb_cMRTrack, "nevents", s_MRTrack_Count, 0);
	rb_define_method(rb_cMRTrack, "count_midi", s_MRTrack_CountMIDI, 0);
	rb_define_method(rb_cMRTrack, "nmidievents", s_MRTrack_CountMIDI, 0);
	rb_define_method(rb_cMRTrack, "count_sysex", s_MRTrack_CountSysex, 0);
	rb_define_method(rb_cMRTrack, "nsysexevents", s_MRTrack_CountSysex, 0);
	rb_define_method(rb_cMRTrack, "count_meta", s_MRTrack_CountMeta, 0);
	rb_define_method(rb_cMRTrack, "nmetaevents", s_MRTrack_CountMeta, 0);
	rb_define_method(rb_cMRTrack, "pointer", s_MRTrack_Pointer, 1);
	rb_define_method(rb_cMRTrack, "event", s_MRTrack_Pointer, 1);
	rb_define_method(rb_cMRTrack, "channel", s_MRTrack_Channel, 0);
	rb_define_method(rb_cMRTrack, "channel=", s_MRTrack_SetChannel, 1);
	rb_define_method(rb_cMRTrack, "device", s_MRTrack_Device, 0);
	rb_define_method(rb_cMRTrack, "device=", s_MRTrack_SetDevice, 1);
	rb_define_method(rb_cMRTrack, "name", s_MRTrack_Name, 0);
	rb_define_method(rb_cMRTrack, "name=", s_MRTrack_SetName, 1);
	rb_define_method(rb_cMRTrack, "selection", s_MRTrack_Selection, 0);
	rb_define_method(rb_cMRTrack, "selection=", s_MRTrack_SetSelection, 1);
	rb_define_method(rb_cMRTrack, "eventset", s_MRTrack_EventSet, -1);
	rb_define_method(rb_cMRTrack, "all_events", s_MRTrack_AllEvents, 0);
	rb_define_method(rb_cMRTrack, "selected?", s_MRTrack_SelectedP, 0);
	rb_define_method(rb_cMRTrack, "editable?", s_MRTrack_EditableP, 0);
	rb_define_method(rb_cMRTrack, "each", s_MRTrack_Each, 0);
	rb_define_method(rb_cMRTrack, "each_selected", s_MRTrack_EachSelected, 0);
	rb_define_method(rb_cMRTrack, "each_in", s_MRTrack_EachIn, 1);
	rb_define_method(rb_cMRTrack, "reverse_each", s_MRTrack_ReverseEach, 0);
	rb_define_method(rb_cMRTrack, "reverse_each_selected", s_MRTrack_ReverseEachSelected, 0);
	rb_define_method(rb_cMRTrack, "reverse_each_in", s_MRTrack_ReverseEachIn, 1);
	rb_define_method(rb_cMRTrack, "merge", s_MRTrack_Merge, -1);
	rb_define_method(rb_cMRTrack, "copy", s_MRTrack_Copy, 1);
	rb_define_method(rb_cMRTrack, "cut", s_MRTrack_Cut, 1);
	rb_define_method(rb_cMRTrack, "add", s_MRTrack_Add, -2);
	rb_define_method(rb_cMRTrack, "<<", s_MRTrack_Add, 1);
}
