/*
 *  MDRubySequence.m
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/03/21.
 *  Copyright 2008-2017 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#include "MDRuby.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#import "MyAppController.h"
#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "MDObjects.h"

//  Sequence class
VALUE rb_cMRSequence = Qfalse;

#pragma mark ====== Housekeeping MyDocument ======

//  Housekeeping MyDocument and Sequence
//  In the constructor of MyDocument, MRSequenceRegister() is called, which
//  creates a new Ruby object which wraps "doc" and registers it in a global
//  Ruby variable $mr_documents. Subsequent request of Sequence always returns
//  this same object for the same MyDocument.
//  When MyDocument is deallocated, MRSequenceUnregister() is called, which
//  removes the Sequence object from $mr_documents, and replace the pointer
//  to MyDocument with nil. Subsequent request of Sequence reeturns Qnil.

//  Global variable $mr_documents
VALUE gMRSequences = Qfalse;

//  Structure to hold a pointer to MyDocument (or nil)
typedef struct MRSequenceRecord {
	MyDocument *doc;
} MRSequenceRecord;

//  MyDocument <-> Sequence
MyDocument *
MyDocumentFromMRSequenceValue(VALUE val)
{
	MRSequenceRecord *rp;
	if (rb_obj_is_kind_of(val, rb_cMRSequence)) {
		Data_Get_Struct(val, MRSequenceRecord, rp);
		if (rp->doc != NULL)
			return rp->doc;
	}
	rb_raise(rb_eTypeError, "Cannot get MyDocument pointer from object");
}

VALUE
MRSequenceFromMyDocument(MyDocument *doc)
{
	VALUE *valp;
	int len, i;
	MRSequenceRecord *rp;
	len = (int)RARRAY_LEN(gMRSequences);
	valp = RARRAY_PTR(gMRSequences);
	for (i = 0; i < len; i++) {
		Data_Get_Struct(valp[i], MRSequenceRecord, rp);
		if (rp->doc == doc)
			return valp[i];  //  Already registered
	}
	return Qnil;
}

int
MRSequenceRegister(void *myDocument)
{
	VALUE val;
	MRSequenceRecord *rp;

	val = MRSequenceFromMyDocument(myDocument);
	if (val != Qnil)
		return -1;  //  Already registered

	//  Register a new entry
	val = Data_Make_Struct(rb_cMRSequence, MRSequenceRecord, 0, -1, rp);
	rp->doc = myDocument;
	rb_ary_push(gMRSequences, val);
	return 0;
}

int
MRSequenceUnregister(void *myDocument)
{
	VALUE val;
	MRSequenceRecord *rp;

	val = MRSequenceFromMyDocument(myDocument);
	if (val == Qnil)
		return -1;  //  Unknown object
	
	Data_Get_Struct(val, MRSequenceRecord, rp);
	rp->doc = nil;
	rb_ary_delete(gMRSequences, val);
	return 0;
}

#pragma mark ====== Ruby methods ======

/*
 *  call-seq:
 *     sequence.tick_to_time(tick)
 *
 *  Convert tick to time by referring the conductor track. Time is expressed
 *  in seconds.
 */
static VALUE
s_MRSequence_TickToTime(VALUE self, VALUE tval)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	MDCalibrator *calib = [[doc myMIDISequence] sharedCalibrator];
	MDTickType tick = (MDTickType)floor(NUM2DBL(tval) + 0.5);
	MDTimeType time = MDCalibratorTickToTime(calib, tick);
	return rb_float_new((double)time / 1000000.0);
}

/*
 *  call-seq:
 *     sequence.time_to_tick(time)
 *
 *  Convert tick to time by referring the conductor track. Time is expressed
 *  in seconds.
 */
static VALUE
s_MRSequence_TimeToTick(VALUE self, VALUE tval)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	MDCalibrator *calib = [[doc myMIDISequence] sharedCalibrator];
	MDTimeType time = (MDTimeType)floor((NUM2DBL(tval) * (double)1000000.0) + (double)0.5);
	MDTickType tick = MDCalibratorTimeToTick(calib, time);
	return rb_float_new((double)tick);
}

/*
 *  call-seq:
 *     sequence.tick_to_measure(tick)
 *
 *  Convert tick to bar/beat/subtick by referring the conductor track. Returns an
 *  array containing three integers. Bar and beat are 1-based, and subtick is
 *  0-based.
 */
static VALUE
s_MRSequence_TickToMeasure(VALUE self, VALUE tval)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	MDCalibrator *calib = [[doc myMIDISequence] sharedCalibrator];
	MDTickType tick = (MDTickType)floor(NUM2DBL(tval) + 0.5);
	int32_t bar, beat, subtick;
	VALUE vals[3];
	MDCalibratorTickToMeasure(calib, tick, &bar, &beat, &subtick);
	vals[0] = INT2NUM(bar);
	vals[1] = INT2NUM(beat);
	vals[2] = INT2NUM(subtick);
	return rb_ary_new4(3, vals);
}

/*
 *  call-seq:
 *     sequence.measure_to_tick(ary)
 *
 *  Convert bar/beat/subtick to tick by referring the conductor track. Ary must
 *  be an array containing three numbers, bar/beat/subtick. Bar and beat are 
 *  1-based, and subtick is 0-based.
 */
static VALUE
s_MRSequence_MeasureToTick(int argc, VALUE *argv, VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	MDCalibrator *calib = [[doc myMIDISequence] sharedCalibrator];
	MDTickType tick;
	VALUE val1, val2, val3;
	int32_t bar, beat, subtick;
	rb_scan_args(argc, argv, "12", &val1, &val2, &val3);
	if (NIL_P(val2) && NIL_P(val3)) {
		bar = NUM2INT(Ruby_ObjectAtIndex(val1, 0));
		beat = NUM2INT(Ruby_ObjectAtIndex(val2, 1));
		subtick = NUM2INT(Ruby_ObjectAtIndex(val3, 2));
	} else {
		bar = NUM2INT(val1);
		beat = NUM2INT(val2);
		subtick = NUM2INT(val3);
	}
	tick = MDCalibratorMeasureToTick(calib, bar, beat, subtick);
	return rb_float_new((double)tick);
}

/*
 *  call-seq:
 *     sequence.tick_for_selection(editable_only = false)
 *
 *  Returns a pair of ticks representing the tick range of selected events.
 *  If the argument is true, then only the editable tracks are examined.
 */
static VALUE
s_MRSequence_TickForSelection(int argc, VALUE *argv, VALUE self)
{
	VALUE fval, startval, endval;
	MDTickType startTick, endTick;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	rb_scan_args(argc, argv, "01", &fval);
	[doc getSelectionStartTick: &startTick endTick: &endTick editableTracksOnly: RTEST(fval)];
	startval = INT2NUM(startTick);
	endval = INT2NUM(endTick);
	return rb_ary_new3(2, startval, endval);
}

/*
 *  call-seq:
 *     sequence.editing_range
 *
 *  Returns a pair of ticks representing the editing range.
 *  If editing range is not set, [-1, -1] is returned.
 */
static VALUE
s_MRSequence_EditingRange(VALUE self)
{
	MDTickType startTick, endTick;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	[doc getEditingRangeStart:&startTick end:&endTick];
	return rb_ary_new3(2, INT2NUM(startTick), INT2NUM(endTick));
}

/*
 *  call-seq:
 *     sequence.timebase
 *
 *  Get the timebase of the sequence in tick.
 */
static VALUE
s_MRSequence_Timebase(VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	float timebase = [doc timebase];
	return rb_float_new(timebase);
}

/*
 *  call-seq:
 *     sequence.set_timebase(timebase)
 *
 *  Set the timebase of the sequence.
 */
static VALUE
s_MRSequence_SetTimebase(VALUE self, VALUE tval)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	float timebase = (float)NUM2DBL(rb_Float(tval));
	[doc setTimebase:timebase];
	return self;
}

/*
 *  call-seq:
 *     sequence.duration
 *
 *  Get the duration of the sequence in tick.
 */
static VALUE
s_MRSequence_Duration(VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	MDTickType duration = [[doc myMIDISequence] sequenceDuration];
	return INT2NUM(duration);
}

/*
 *  call-seq:
 *     sequence.track(n)
 *
 *  Get an Track object containing the n-th track.
 */
static VALUE
s_MRSequence_Track(VALUE self, VALUE nval)
{
	return rb_funcall(rb_cMRTrack, rb_intern("new"), 2, self, nval);
}

/*
 *  call-seq:
 *     sequence.number_of_tracks
 *     sequence.ntracks
 *
 *  Get the duration of the sequence in tick.
 */
static VALUE
s_MRSequence_NumberOfTracks(VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	int ntracks = [[doc myMIDISequence] trackCount];
	return INT2NUM(ntracks);
}

/*
 *  call-seq:
 *     sequence.each_track block
 *
 *  Execute the block for each track; the block argument is a Track object.
 */
static VALUE
s_MRSequence_EachTrack(VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	int ntracks = [[doc myMIDISequence] trackCount];
	int i;
	for (i = 0; i < ntracks; i++) {
		VALUE tval = s_MRSequence_Track(self, INT2NUM(i));
		rb_yield(tval);
	}
	return self;
}

/*
 *  call-seq:
 *     sequence.each_editable_track block
 *
 *  Execute the block for each editable track; the block argument is a Track object.
 */
static VALUE
s_MRSequence_EachEditableTrack(VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	int ntracks = [[doc myMIDISequence] trackCount];
	int i;
	for (i = 0; i < ntracks; i++) {
		MDTrackAttribute attr = [doc trackAttributeForTrack: i];
		if (attr & kMDTrackAttributeEditable) {
			VALUE tval = s_MRSequence_Track(self, INT2NUM(i));
			rb_yield(tval);
		}
	}
	return self;
}

/*
 *  call-seq:
 *     sequence.each_selected_track block
 *
 *  Execute the block for each selected track; the block argument is a Track object.
 */
static VALUE
s_MRSequence_EachSelectedTrack(VALUE self)
{
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	int ntracks = [[doc myMIDISequence] trackCount];
	int i;
	for (i = 0; i < ntracks; i++) {
		if ([doc isTrackSelected: i]) {
			VALUE tval = s_MRSequence_Track(self, INT2NUM(i));
			rb_yield(tval);
		}
	}
	return self;
}

/*
 *  call-seq:
 *     sequence.insert_track(track[, num]) -> track
 *
 *  Insert a track at the specified position, or at the end if unspecified.
 *  The track must not belong to any sequence (including self).
 */
static VALUE
s_MRSequence_InsertTrack(int argc, VALUE *argv, VALUE self)
{
	VALUE tval, nval;
	int n;
	MyDocumentTrackInfo *ip;
	MDTrackObject *trobj;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	rb_scan_args(argc, argv, "11", &tval, &nval);
	ip = TrackInfoFromMRTrackValue(tval);
	if (ip->doc != nil)
		rb_raise(rb_eArgError, "The track to insert must not belong to any sequence");
	if (nval == Qnil)
		n = [[doc myMIDISequence] trackCount];
	else
		n = NUM2INT(rb_Integer(nval));
	trobj = [[[MDTrackObject alloc] initWithMDTrack: ip->track] autorelease];
	[doc insertTrack: trobj atIndex: n];
	/*  ip->doc is automatically updated  */
	return tval;
}

/*
 *  call-seq:
 *     sequence.delete_track(num) -> track
 *
 *  Delete a track at the specified position.  Returns the deleted track,
 *  which has now no parent.
 */
static VALUE
s_MRSequence_DeleteTrack(VALUE self, VALUE nval)
{
	int n;
	VALUE rval;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	n = NUM2INT(rb_Integer(nval));
	if (n < 0 || n >= [[doc myMIDISequence] trackCount])
		rb_raise(rb_eRangeError, "track number out of range");
	rval = s_MRSequence_Track(self, nval);
	[doc deleteTrackAt: n];
	/*  Note: the MDTrack contained in rval is now orphaned. The deleted track
	    is also on the undo buffer of the document, but it is a duplicated copy.
	    See -[MyDocument deleteTrackAt:].  */
	return rval;
}

/*
 *  call-seq:
 *     sequence.name -> String
 *
 *  Get the name of the sequence.
 */
static VALUE
s_MRSequence_Name(VALUE self)
{
//	int n;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	NSString *name = [doc tuneName];
	return rb_str_new2([name UTF8String]);
}

/*
 *  call-seq:
 *     sequence.path -> String
 *
 *  Get the path of the sequence, if it is associated with a file.
 */
static VALUE
s_MRSequence_Path(VALUE self)
{
//	int n;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	NSURL *url = [doc fileURL];
	NSString *path;
	if (url != nil && (path = [url path]) != nil)
		return rb_str_new2([path UTF8String]);
	else return Qnil;
}

/*
 *  call-seq:
 *     sequence.dir -> String
 *
 *  Get the directory of the sequence, if it is associated with a file.
 */
static VALUE
s_MRSequence_Dir(VALUE self)
{
//	int n;
	MyDocument *doc = MyDocumentFromMRSequenceValue(self);
	NSURL *url = [doc fileURL];
	NSString *path;
	if (url != nil && (path = [url path]) != nil) {
		path = [path stringByDeletingLastPathComponent];
		return rb_str_new2([path UTF8String]);
	} else return Qnil;
}

/*
 *  call-seq:
 *     Sequence.current
 *
 *  Get the sequence corresponding to the current document.
 */
VALUE
MRSequence_Current(VALUE self)
{
	NSArray *docs = [NSApp orderedDocuments];
	if (docs == nil || [docs count] == 0)
		return Qnil;
	return MRSequenceFromMyDocument([docs objectAtIndex: 0]);
}

/*  For DEBUG  */
VALUE
s_MRSequence_Merger(int argc, VALUE *argv, VALUE self)
{
    int i;
    MyDocument *doc = MyDocumentFromMRSequenceValue(self);
    MyMIDISequence *seq = [doc myMIDISequence];
    MDTrackMerger *merger = MDTrackMergerNew();
    MDTrack *track;
    int numEvents = 0;
    MDEvent **ebuf, *ep;
    char buf[256];
    FILE *fp;
    int *ibuf;
    for (i = 0; i < argc; i++) {
        int n = NUM2INT(argv[i]);
        track = [seq getTrackAtIndex:n];
        if (track != NULL) {
            MDTrackMergerAddTrack(merger, track);
            numEvents += MDTrackGetNumberOfEvents(track);
        }
    }
    ebuf = (MDEvent **)calloc(sizeof(MDEvent *), numEvents);
    ibuf = (int *)calloc(sizeof(int), numEvents);
    if (ebuf == NULL || ibuf == NULL) {
        fprintf(stderr, "out of memory\n");
        return Qnil;
    }
    ep = MDTrackMergerCurrent(merger, &track);
    fp = fopen([[@"~/merger_test.txt" stringByExpandingTildeInPath] UTF8String], "w");
    if (fp == NULL) {
        fprintf(stderr, "Cannot open merger_test.txt\n");
        return Qnil;
    }
    for (i = 0; i < numEvents && ep != NULL; i++) {
        int trno = [seq lookUpTrack:track];
        ebuf[i] = ep;
        ibuf[i] = trno;
        MDEventToString(ep, buf, sizeof(buf));
        fprintf(fp, "%d:%s\n", trno, buf);
        ep = MDTrackMergerForward(merger, &track);
    }
    fclose(fp);
    free(ebuf);
    free(ibuf);
    return INT2NUM(numEvents);
}

VALUE
s_MRSequence_BackMerger(int argc, VALUE *argv, VALUE self)
{
    int i;
    MyDocument *doc = MyDocumentFromMRSequenceValue(self);
    MyMIDISequence *seq = [doc myMIDISequence];
    MDTrackMerger *merger = MDTrackMergerNew();
    MDTrack *track;
    int numEvents = 0;
    MDEvent **ebuf, *ep;
    char buf[256];
    FILE *fp;
    int *ibuf;
    for (i = 0; i < argc; i++) {
        int n = NUM2INT(argv[i]);
        track = [seq getTrackAtIndex:n];
        if (track != NULL) {
            MDTrackMergerAddTrack(merger, track);
            numEvents += MDTrackGetNumberOfEvents(track);
        }
    }
    ebuf = (MDEvent **)calloc(sizeof(MDEvent *), numEvents);
    ibuf = (int *)calloc(sizeof(int), numEvents);
    if (ebuf == NULL || ibuf == NULL) {
        fprintf(stderr, "out of memory\n");
        return Qnil;
    }
    MDTrackMergerJumpToTick(merger, kMDMaxTick, NULL);
    fp = fopen([[@"~/backmerger_test.txt" stringByExpandingTildeInPath] UTF8String], "w");
    if (fp == NULL) {
        fprintf(stderr, "Cannot open backmerger_test.txt\n");
        return Qnil;
    }
    for (i = numEvents - 1; i >= 0; i--) {
        int trno;
        ep = MDTrackMergerBackward(merger, &track);
        if (ep == NULL)
            break;
        trno = [seq lookUpTrack:track];
        ebuf[i] = ep;
        ibuf[i] = trno;
    }
    for (i = 0; i < numEvents; i++) {
        MDEventToString(ebuf[i], buf, sizeof(buf));
        fprintf(fp, "%d:%s\n", ibuf[i], buf);
    }
    fclose(fp);
    free(ebuf);
    free(ibuf);
    return INT2NUM(numEvents);
}

#if 0
 static id
s_ObjCFromValue(VALUE val)
{
	switch (TYPE(val)) {
		case T_NIL: return [NSNull null];
		case T_FLOAT: return [NSNumber numberWithDouble: NUM2DBL(val)];
		case T_STRING: return [NSString stringWithUTF8String: RSTRING_PTR(val)];
		case T_ARRAY: {
			int n = RARRAY_LEN(val);
			VALUE *p = RARRAY_PTR(val);
			int i;
			NSMutableArray *array = [NSMutableArray array];
			for (i = 0; i < n; i++)
				[array addObject: s_ObjCFromValue(p[i])];
			return array;
		}
		case T_FIXNUM:
		case T_BIGNUM:
			return [NSNumber numberWithInt: NUM2INT(val)];
		case T_HASH: {
			int i;
			VALUE keys = rb_funcall(val, rb_intern("keys"), 0);
			int klen = RARRAY_LEN(keys);
			VALUE *kptr = RARRAY_PTR(keys);
			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			for (i = 0; i < klen; i++)
				[dict setObject: s_ObjCFromValue(kptr[i]) forKey: s_ObjCFromValue(kptr[i])];
			return dict;
		}
		case T_TRUE:
		case T_FALSE:
			return [NSNumber numberWithBool: (val != Qfalse)];
		default: {
			VALUE mval = rb_marshal_dump(val, Qnil);
			return [NSData dataWithBytes: RSTRING_PTR(mval) length: RSTRING_LEN(mval)];
		}
	}
}

static VALUE
s_ValueFromObjC(id obj)
{
	if (obj == nil)
		return Qnil;
	else if ([obj isKindOfClass: [NSNumber class]]) {
		char c = [obj objCType][0];
		if (c == 'f' || c == 'd')
			return rb_float_new([obj doubleValue]);
		else {
			int ival = [obj intValue];
			if (c == 'B' || ((c == 'c' || c == 'C') && (ival == 0 || ival == 1)))
				return (ival ? Qtrue : Qfalse);
			else return INT2NUM(ival);
		}
	} else if ([obj isKindOfClass: [NSString class]]) {
		return rb_str_new2([obj UTF8String]);
	} else if ([obj isKindOfClass: [NSArray class]]) {
		VALUE ary = rb_ary_new();
		id obj2;
		NSEnumerator *en = [obj objectEnumerator];
		while ((obj2 = [en nextObject]) != nil)
			rb_ary_push(ary, s_ValueFromObjC(obj2));
		return ary;
	} else if ([obj isKindOfClass: [NSDictionary class]]) {
		VALUE hash = rb_hash_new();
		id obj2;
		NSEnumerator *ken = [obj keyEnumerator];
		while ((obj2 = [ken nextObject]) != nil)
			rb_hash_aset(hash, s_ValueFromObjC(obj2), s_ValueFromObjC([obj objectForKey: obj2]));
		return hash;
	} else if ([obj isKindOfClass: [NSNull class]]) {
		return Qnil;
	} else if ([obj isKindOfClass: [NSData class]]) {
		VALUE mval = rb_str_new([obj bytes], [obj length]);
		return rb_marshal_load(mval);
	} else {
		rb_raise(rb_eTypeError, "Cannot convert objective-C object to a ruby object: %s", [[obj description] UTF8String]);
		return Qnil;  /*  Not reached  */
	}
}
#endif

#if 0
#pragma mark ------ Unused ------
/*
 *  call-seq:
 *     Sequence.global_settings(key)
 *
 *  Get a setting data for key from NSUserDefaults.
 */
VALUE
MRSequence_GlobalSettings(VALUE self, VALUE key)
{
	NSString *skey = [NSString stringWithUTF8String: StringValuePtr(key)];
	id obj = [[[NSUserDefaults standardUserDefaults] objectForKey: @"MDRuby"] objectForKey: skey];
	return s_ValueFromObjC(obj);
}

/*
 *  call-seq:
 *     Sequence.set_global_settings(key, value)
 *
 *  Set a setting data for key to NSUserDefaults.
 */
VALUE
MRSequence_SetGlobalSettings(VALUE self, VALUE key, VALUE value)
{
	NSString *skey = [NSString stringWithUTF8String: StringValuePtr(key)];
	id obj = s_ObjCFromValue(value);
	id dict = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] objectForKey: @"MDRuby"]];
	[dict setObject: obj forKey: skey];
	[[NSUserDefaults standardUserDefaults] setObject: dict forKey: @"MDRuby"];
	return value;
}

/*
 *  call-seq:
 *     sequence.register_menu(title, method)
 *
 *  Register the method (specified as a symbol) in the script menu. If called
 *  as a usual method, the menu command is specific to the document. If called
 *  as a class method, the menu command is globally visible from all documents.
 */
static VALUE
s_MRSequence_RegisterMenu(VALUE self, VALUE title, VALUE method)
{
	MyDocument *doc;
	NSString *commandName, *menuTitle;
	if (rb_obj_is_kind_of(self, rb_cMRSequence)) {
		MRSequenceRecord *rp;
		Data_Get_Struct(self, MRSequenceRecord, rp);
		doc = rp->doc;
	} else {
		doc = nil;
	}
	menuTitle = [NSString stringWithUTF8String: StringValuePtr(title)];
	if (TYPE(method) == T_SYMBOL) {
		method = rb_funcall(method, rb_intern("to_s"), 0);
	}
	commandName = [NSString stringWithUTF8String: StringValuePtr(method)];
	[[NSApp delegate] registerScriptMenu: commandName withTitle: menuTitle forDocument: doc];
	return self;
}

#endif

#pragma mark ====== Evaluate string (unused) ======

#if 0
int
MDRubyLoadScriptUnderMRSequence(const char *fname)
{
	int state;
	NSString *err = nil;
	VALUE val;
	NSString *basename;
	static const char *mes1 = "class Sequence\n";
	static const char *mes2 = "\nend\n";
	char *p;
	struct stat st;
	off_t size;
	int s1, s2, fd;
	
	basename = [[NSString stringWithUTF8String: fname] lastPathComponent];
	
	//  Evaluate a string "class Sequence\n(file content)\nend\n"
	if (stat(fname, &st) != 0) {
		err = [NSString stringWithFormat: @"Cannot get file size of %f", fname];
		goto error;
	}
	size = st.st_size;
	s1 = strlen(mes1);
	s2 = strlen(mes2);
	p = (char *)malloc(size + s1 + s2 + 1);
	if (p == NULL) {
		err = @"Out of memory";
		goto error;
	}
	fd = open(fname, O_RDONLY);
	if (fd < 0) {
		free(p);
		err = [NSString stringWithFormat: @"Cannot open script %s", fname];
		goto error;
	}
	strcpy(p, mes1);
	if (read(fd, p + s1, size) < size) {
		free(p);
		close(fd);
		err = [NSString stringWithFormat: @"Cannot read contents of file %s", fname];
		goto error;
	}
	close(fd);
	strcpy(p + s1 + size, mes2);
	val = rb_eval_string_protect(p, &state);
	free(p);
	if (state != 0) {
		NSString *str = [NSString stringWithFormat: @"$!.to_s.gsub(/\\(eval\\)/,\"%@\")", basename];
		val = rb_eval_string_protect([str UTF8String], &state);
		err = [NSString stringWithUTF8String: StringValuePtr(val)];
		goto error;
	}
	return val;
  error:
	NSLog(@"MDRuby error: %@", err);
	return Qnil;
}

static VALUE
sMDRubyCallMethodOfMRSequence(VALUE arg)
{
	VALUE *vals = (VALUE *)arg;
	MyDocument *doc = (MyDocument *)vals[0];
	const char *method = (const char *)vals[1];
	int argc = (int)vals[2];
	VALUE *argv = (VALUE *)vals[3];
	VALUE retval;
	ID method_id;
	VALUE docval = MRSequenceFromMyDocument(doc);
	if (docval == Qfalse)
		rb_raise(rb_eStandardError, "Cannot get document object");
	method_id = rb_intern(method);
	retval = rb_funcall2(docval, method_id, argc, argv);
	MRPointerSendAllCachedEventModifications();  /*  Flush pending modifications  */
	return retval;
}

void
MDRubyCallMethodOfMRSequence(MyDocument *doc, const char *method, int argc, VALUE *argv)
{
	VALUE vals[4];
	int state;
	NSString *err;
	vals[0] = (VALUE)doc;
	vals[1] = (VALUE)method;
	vals[2] = (VALUE)argc;
	vals[3] = (VALUE)argv;
	rb_protect(sMDRubyCallMethodOfMRSequence, (VALUE)vals, &state);
	if (state == 0)
		return;
	vals[0] = rb_eval_string_protect("$!.to_s", &state);
	err = [NSString stringWithUTF8String: StringValuePtr(vals[0])];
//	NSLog(@"MDRuby error: %@", err);
	state = NSRunAlertPanel(@"MDRuby error", err, nil, nil, nil);
}
#endif

#pragma mark ====== Initialize class ======

void
MRSequenceInitClass(void)
{
	if (rb_cMRSequence != Qfalse)
		return;

	rb_cMRSequence = rb_define_class("Sequence", rb_cObject);

	//  Define methods
/*    rb_define_method(rb_cMRSequence, "register_menu", s_MRSequence_RegisterMenu, 2); */
    rb_define_method(rb_cMRSequence, "tick_to_time", s_MRSequence_TickToTime, 1);
    rb_define_method(rb_cMRSequence, "time_to_tick", s_MRSequence_TimeToTick, 1);
    rb_define_method(rb_cMRSequence, "tick_to_measure", s_MRSequence_TickToMeasure, 1);
    rb_define_method(rb_cMRSequence, "measure_to_tick", s_MRSequence_MeasureToTick, -1);
    rb_define_method(rb_cMRSequence, "tick_for_selection", s_MRSequence_TickForSelection, -1);
    rb_define_method(rb_cMRSequence, "editing_range", s_MRSequence_EditingRange, 0);
	rb_define_method(rb_cMRSequence, "timebase", s_MRSequence_Timebase, 0);
	rb_define_method(rb_cMRSequence, "set_timebase", s_MRSequence_SetTimebase, 1);
    rb_define_method(rb_cMRSequence, "duration", s_MRSequence_Duration, 0);
    rb_define_method(rb_cMRSequence, "track", s_MRSequence_Track, 1);
    rb_define_method(rb_cMRSequence, "number_of_tracks", s_MRSequence_NumberOfTracks, 0);
    rb_define_method(rb_cMRSequence, "ntracks", s_MRSequence_NumberOfTracks, 0);
	rb_define_method(rb_cMRSequence, "each_track", s_MRSequence_EachTrack, 0);
	rb_define_method(rb_cMRSequence, "each_editable_track", s_MRSequence_EachEditableTrack, 0);
	rb_define_method(rb_cMRSequence, "each_selected_track", s_MRSequence_EachSelectedTrack, 0);
	rb_define_method(rb_cMRSequence, "insert_track", s_MRSequence_InsertTrack, -1);
	rb_define_method(rb_cMRSequence, "delete_track", s_MRSequence_DeleteTrack, 1);
	rb_define_method(rb_cMRSequence, "name", s_MRSequence_Name, 0);
	rb_define_method(rb_cMRSequence, "path", s_MRSequence_Path, 0);
	rb_define_method(rb_cMRSequence, "dir", s_MRSequence_Dir, 0);
	
    /*  for DEBUG  */
    rb_define_method(rb_cMRSequence, "merger", s_MRSequence_Merger, -1);
    rb_define_method(rb_cMRSequence, "backmerger", s_MRSequence_BackMerger, -1);

/*    rb_define_method(rb_cMRSequence, "pointer", s_MRSequence_Pointer, 1); */
    rb_define_singleton_method(rb_cMRSequence, "current", MRSequence_Current, 0);

/*    rb_define_singleton_method(rb_cMRSequence, "register_menu", s_MRSequence_RegisterMenu, 2);
    rb_define_singleton_method(rb_cMRSequence, "global_settings", MRSequence_GlobalSettings, 1);
    rb_define_singleton_method(rb_cMRSequence, "set_global_settings", MRSequence_SetGlobalSettings, 2); */

	//  Define a global variable "$mr_documents" and assign an empty array
	rb_define_variable("mr_documents", &gMRSequences);
	gMRSequences = rb_ary_new();
}
