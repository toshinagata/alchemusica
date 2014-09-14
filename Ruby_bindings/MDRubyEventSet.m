/*
 *  MDRubyEventSet.m
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 09/01/24.
 *  Copyright 2009-2011 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDRubyEventSet.h"
#include "MDRubyTrack.h"
#include "MDRubyPointer.h"
#import "MyDocument.h"
#import "MDObjects.h"

#pragma mark ====== MRPointSet Class ======

/*  The MRPointSet class is dependent only on MDPointSet  */

VALUE rb_cMRPointSet;

MDPointSet *
MDPointSetFromValue(VALUE val)
{
	MDPointSet *pset;
	if (!rb_obj_is_kind_of(val, rb_cMRPointSet))
		val = rb_funcall(rb_cMRPointSet, rb_intern("new"), 1, val);
	Data_Get_Struct(val, MDPointSet, pset);
	return pset;
}

VALUE
ValueFromMDPointSet(MDPointSet *pset)
{
	if (pset == NULL)
		return Qnil;
	MDPointSetRetain(pset);
    return Data_Wrap_Struct(rb_cMRPointSet, 0, (void (*)(void *))MDPointSetRelease, pset);
}

void
MRPointSet_RaiseIfError(int err)
{
	if (err != 0) {
		const char *s;
		switch (err) {
			case kMDErrorOutOfMemory: s = "out of memory"; break;
			case kMDErrorOutOfRange: s = "out of range"; break;
			default: s = ""; break;
		}
		rb_raise(rb_eStandardError, "%s error occurred during MDPointSet operation", s);
	}
}

/*  Allocator  */
VALUE
MRPointSet_Alloc(VALUE klass)
{
	MDPointSet *pset = MDPointSetNew();
    return Data_Wrap_Struct(klass, 0, (void (*)(void *))MDPointSetRelease, pset);
}

/*  Iterator block for initializer  */
static VALUE
s_MRPointSet_Initialize_i(VALUE val, VALUE pset1)
{
	MRPointSet_RaiseIfError(MDPointSetAdd((MDPointSet *)pset1, NUM2INT(val), 1));
	return Qnil;
}

/*
 *  call-seq:
 *     MRPointSet.new(arg1, arg2, ...)
 *     MRPointSet.new(arg1, arg2, ...) { |n| ... }
 *
 *  Create a new pointset. Arg1, arg2,... are one of the following: MRPointSet, Range, 
 *  Enumerable, Integer.
 *  If a block is given, it is executed for each element in the arguments, and
 *  a new pointset including the returned value (only non-negative integers) is returned.
 */
static VALUE
s_MRPointSet_Initialize(int argc, VALUE *argv, VALUE self)
{
	MDPointSet *pset1;
	Data_Get_Struct(self, MDPointSet, pset1);
	while (argc-- > 0) {
		VALUE arg = *argv++;
		int type = TYPE(arg);
		if (rb_obj_is_kind_of(arg, rb_cMRPointSet))
			rb_funcall(rb_cMRPointSet, rb_intern("merge"), 1, arg);
		else if (rb_obj_is_kind_of(arg, rb_cRange)) {
			int sp, ep;
			sp = NUM2INT(rb_funcall(arg, rb_intern("begin"), 0));
			ep = NUM2INT(rb_funcall(arg, rb_intern("end"), 0));
			if (RTEST(rb_funcall(arg, rb_intern("exclude_end?"), 0)))
				ep--;
			if (ep >= sp)
				MRPointSet_RaiseIfError(MDPointSetAdd(pset1, sp, ep - sp + 1));
		} else if (rb_respond_to(arg, rb_intern("each")) && type != T_STRING)
			rb_iterate(rb_each, arg, s_MRPointSet_Initialize_i, (VALUE)pset1);
		else
			MRPointSet_RaiseIfError(MDPointSetAdd(pset1, NUM2INT(arg), 1));
	}
	if (rb_block_given_p()) {
		MDPointSet *pset2 = MDPointSetNew();
		int i, n;
		for (i = 0; (n = MDPointSetGetNthPoint(pset1, i)) >= 0; i++) {
			n = NUM2INT(rb_yield(INT2NUM(n)));
			if (n >= 0)
				MRPointSet_RaiseIfError(MDPointSetAdd(pset2, n, 1));
		}
		MRPointSet_RaiseIfError(MDPointSetCopy(pset1, pset2));
	}
	return Qnil;
}

/*
 *  call-seq:
 *     pointset.clear
 *
 *  Empty the pointset.
 */
static VALUE
s_MRPointSet_Clear(VALUE self)
{
	MDPointSet *pset;
	Data_Get_Struct(self, MDPointSet, pset);
	MDPointSetClear(pset);
	return self;
}

/*
 *  call-seq:
 *     pointset.dup
 *
 *  Duplicate the pointset.
 */
static VALUE
s_MRPointSet_InitializeCopy(VALUE self, VALUE val)
{
	MDPointSet *pset1, *pset2;
	Data_Get_Struct(self, MDPointSet, pset1);
	if (!rb_obj_is_kind_of(val, rb_cMRPointSet))
		rb_raise(rb_eTypeError, "MDPointSet instance is expected");
    Data_Get_Struct(val, MDPointSet, pset2);
	MDPointSetCopy(pset1, pset2);
	return self;
}

/*
 *  call-seq:
 *     pointset.length
 *
 *  Returns the number of points in the pointset.
 */
static VALUE
s_MRPointSet_Length(VALUE self)
{
	MDPointSet *pset;
	Data_Get_Struct(self, MDPointSet, pset);
	return INT2NUM(MDPointSetGetCount(pset));
}

/*
 *  call-seq:
 *     pointset.member?(n)
 *
 *  Check whether the argument is included in the pointset.
 */
static VALUE
s_MRPointSet_MemberP(VALUE self, VALUE val)
{
	MDPointSet *pset;
	int n = NUM2INT(val);
	Data_Get_Struct(self, MDPointSet, pset);
	return (MDPointSetLookup(pset, n, NULL) ? Qtrue : Qfalse);
}

/*
 *  call-seq:
 *     pointset[n]
 *
 *  Returns the n-th point.
 */
static VALUE
s_MRPointSet_ElementAtIndex(VALUE self, VALUE val)
{
	MDPointSet *pset;
	int n;
	int index = NUM2INT(rb_Integer(val));
	Data_Get_Struct(self, MDPointSet, pset);
	n = MDPointSetGetNthPoint(pset, index);
	return (n >= 0 ? INT2NUM(n) : Qnil);
}

/*
 *  call-seq:
 *     pointset.each { |n| ... }
 *
 *  Iterate the block for each point in the set.
 */
static VALUE
s_MRPointSet_Each(VALUE self)
{
	MDPointSet *pset;
	int i, j, sp, ep;
	Data_Get_Struct(self, MDPointSet, pset);
	for (i = 0; (sp = MDPointSetGetStartPoint(pset, i)) >= 0; i++) {
		ep = MDPointSetGetEndPoint(pset, i);
		for (j = sp; j < ep; j++) {
			rb_yield(INT2NUM(j));
		}
	}
	return self;
}

/*
 *  call-seq:
 *     pointset.add(pset2)
 *
 *  Add points in the argument to self.
 */
static VALUE
s_MRPointSet_Add(VALUE self, VALUE val)
{
	MDPointSet *pset, *pset2;
    if (OBJ_FROZEN(self))
		rb_error_frozen("MDPointSet");
	Data_Get_Struct(self, MDPointSet, pset);
	if (rb_obj_is_kind_of(val, rb_cNumeric)) {
		int n = NUM2INT(rb_Integer(val));
		if (n < 0)
			rb_raise(rb_eRangeError, "the integer group can contain only non-negative values");
		MDPointSetAdd(pset, n, 1);
	} else {
		pset2 = MDPointSetFromValue(val);
		MDPointSetAddPointSet(pset, pset2);
	}
	return self;
}

/*
 *  call-seq:
 *     pointset.delete(pset2)
 *
 *  Remove points in the argument from self.
 */
static VALUE
s_MRPointSet_Delete(VALUE self, VALUE val)
{
	MDPointSet *pset, *pset2;
    if (OBJ_FROZEN(self))
		rb_error_frozen("MDPointSet");
	Data_Get_Struct(self, MDPointSet, pset);
	if (rb_obj_is_kind_of(val, rb_cNumeric)) {
		int n = NUM2INT(rb_Integer(val));
		if (n >= 0 && MDPointSetLookup(pset, n, NULL))
			MDPointSetRemove(pset, n, 1);
	} else {
		pset2 = MDPointSetFromValue(val);
		MDPointSetRemovePointSet(pset, pset2);
	}
	return self;
}

/*
 *  call-seq:
 *     pointset.reverse(pset2)
 *
 *  Reverse points in the argument from self.
 */
static VALUE
s_MRPointSet_Reverse(VALUE self, VALUE val)
{
	MDPointSet *pset, *pset2;
    if (OBJ_FROZEN(self))
		rb_error_frozen("MDPointSet");
	Data_Get_Struct(self, MDPointSet, pset);
	if (rb_obj_is_kind_of(val, rb_cNumeric)) {
		int n = NUM2INT(rb_Integer(val));
		if (n >= 0 && MDPointSetLookup(pset, n, NULL))
			MDPointSetReverse(pset, n, 1);
	} else {
		pset2 = MDPointSetFromValue(val);
		MDPointSetReversePointSet(pset, pset2);
	}
	return self;
}

static VALUE
s_MRPointSet_Binary(VALUE self, VALUE val, MDStatus (*func)(const MDPointSet *, const MDPointSet *, MDPointSet *))
{
	MDPointSet *pset1, *pset2, *pset3;
	VALUE retval;
	Data_Get_Struct(self, MDPointSet, pset1);
	pset2 = MDPointSetFromValue(val);
/*	retval = MRPointSet_Alloc(rb_cMRPointSet); */
	retval = rb_obj_dup(self); /* the return value will have the same class as self  */
	Data_Get_Struct(retval, MDPointSet, pset3);
	MDPointSetClear(pset3);
	MRPointSet_RaiseIfError(func(pset1, pset2, pset3));
	return retval;
}

/*
 *  call-seq:
 *     pointset.union(pset2)
 *     pointset + pset2
 *     pointset | pset2
 *
 *	Calculate the union set and return as a new pointset object.
 *  (pointset is first dup'ed, so the instance variables are copied to the returned value).
 */
static VALUE
s_MRPointSet_Union(VALUE self, VALUE val)
{
	return s_MRPointSet_Binary(self, val, MDPointSetUnion);
}

/*
 *  call-seq:
 *     pointset.intersection(pset2)
 *     pointset & pset2
 *
 *	Calculate the intersection set and return as a new pointset object.
 *  (pointset is first dup'ed, so the instance variables are copied to the returned value).
 */
static VALUE
s_MRPointSet_Intersection(VALUE self, VALUE val)
{
	return s_MRPointSet_Binary(self, val, MDPointSetIntersect);
}

/*
 *  call-seq:
 *     pointset.difference(pset2)
 *     pointset - pset2
 *
 *	Calculate the difference set and return as a new pointset object.
 *  (pointset is first dup'ed, so the instance variables are copied to the returned value).
 */
static VALUE
s_MRPointSet_Difference(VALUE self, VALUE val)
{
	return s_MRPointSet_Binary(self, val, MDPointSetDifference);
}

/*
 *  call-seq:
 *     pointset.sym_difference(pset2)
 *     pointset ^ pset2
 *
 *	Calculate the symmetric difference set and return as a new pointset object.
 *  (pointset is first dup'ed, so the instance variables are copied to the returned value).
 */
static VALUE
s_MRPointSet_SymDifference(VALUE self, VALUE val)
{
	return s_MRPointSet_Binary(self, val, MDPointSetXor);
}

/*
 *  call-seq:
 *     pointset.convolute(pset2)
 *
 *	Calculate the convolute set and return as a new pointset object.
 *  (pointset is first dup'ed, so the instance variables are copied to the returned value).
 */
static VALUE
s_MRPointSet_Convolute(VALUE self, VALUE val)
{
	return s_MRPointSet_Binary(self, val, MDPointSetConvolute);
}

/*
 *  call-seq:
 *     pointset.deconvolute(pset2)
 *
 *	Calculate the convolute set and return as a new pointset object.
 *  (pointset is first dup'ed, so the instance variables are copied to the returned value).
 */
static VALUE
s_MRPointSet_Deconvolute(VALUE self, VALUE val)
{
	return s_MRPointSet_Binary(self, val, MDPointSetDeconvolute);
}

/*
 *  call-seq:
 *     pointset.range_at(n)
 *
 *	Regard self as a set of integer ranges, and returns the n-th range as a Range object.
 */
static VALUE
s_MRPointSet_RangeAt(VALUE self, VALUE val)
{
	MDPointSet *pset;
	int n = NUM2INT(val);
	int sp, ep;
	Data_Get_Struct(self, MDPointSet, pset);
	sp = MDPointSetGetStartPoint(pset, n);
	if (sp < 0)
		return Qnil;
	ep = MDPointSetGetEndPoint(pset, n) - 1;
	return rb_funcall(rb_cRange, rb_intern("new"), 2, INT2NUM(sp), INT2NUM(ep));
}

/*
static VALUE
s_MRPointSet_Merge(VALUE self, VALUE val)
{
	MDPointSet *pset1, *pset2;
	int i, sp, interval;
    if (OBJ_FROZEN(self))
		rb_error_frozen("MDPointSet");
	Data_Get_Struct(self, MDPointSet, pset1);
	pset2 = MDPointSetFromValue(val);
	for (i = 0; (sp = MDPointSetGetStartPoint(pset2, i)) >= 0; i++) {
		interval = MDPointSetGetInterval(pset2, i);
		MRPointSet_RaiseIfError(MDPointSetAdd(pset1, sp, interval));
	}
	return self;
}

static VALUE
s_MRPointSet_Subtract(VALUE self, VALUE val)
{
	MDPointSet *pset1, *pset2;
	int i, sp, interval;
    if (OBJ_FROZEN(self))
		rb_error_frozen("MDPointSet");
	Data_Get_Struct(self, MDPointSet, pset1);
	pset2 = MDPointSetFromValue(val);
	for (i = 0; (sp = MDPointSetGetStartPoint(pset2, i)) >= 0; i++) {
		interval = MDPointSetGetInterval(pset2, i);
		MRPointSet_RaiseIfError(MDPointSetRemove(pset1, sp, interval));
	}
	return self;
}
*/

/*
 *  call-seq:
 *     pointset.offset(n)
 *
 *	Offset all points by n. n can be negative, but if it is smaller than the negative
 *  of the first point, an exception is raised.
 */
static VALUE
s_MRPointSet_Offset(VALUE self, VALUE ofs)
{
	MDPointSet *pset1, *pset2;
	int iofs;
	VALUE val;
	Data_Get_Struct(self, MDPointSet, pset1);
	pset2 = MDPointSetNew();
	if (pset2 == NULL || MDPointSetCopy(pset2, pset1) != kMDNoError)
		rb_raise(rb_eTypeError, "Cannot duplicate MDPointSet");
	iofs = NUM2INT(ofs);
	if (MDPointSetOffset(pset2, iofs) != 0)
		rb_raise(rb_eRangeError, "Bad offset %d", iofs);
	val = ValueFromMDPointSet(pset2);
	MDPointSetRelease(pset2);
	return val;
}

static VALUE
s_MRPointSet_Create(int argc, VALUE *argv, VALUE klass)
{
	VALUE val = MRPointSet_Alloc(klass);
	s_MRPointSet_Initialize(argc, argv, val);
	return val;
}

/*
 *  call-seq:
 *     pointset.inspect(n)
 *
 *	Returns the string representation of the pointset.
 */
static VALUE
s_MRPointSet_Inspect(VALUE self)
{
	int i, sp, ep;
	MDPointSet *pset;
	char buf[64];
	VALUE klass = CLASS_OF(self);
	VALUE val = rb_funcall(klass, rb_intern("name"), 0);
	Data_Get_Struct(self, MDPointSet, pset);
	rb_str_cat(val, "[", 1);
	for (i = 0; (sp = MDPointSetGetStartPoint(pset, i)) >= 0; i++) {
		if (i > 0)
			rb_str_cat(val, ", ", 2);
		ep = MDPointSetGetEndPoint(pset, i);
		if (ep > sp + 1)
			snprintf(buf, sizeof buf, "%d..%d", sp, ep - 1);
		else
			snprintf(buf, sizeof buf, "%d", sp);
		rb_str_cat(val, buf, strlen(buf));
	}
	rb_str_cat(val, "]", 1);
	return val;
}

#pragma mark ====== MREventSet Class ======

VALUE rb_cMREventSet;

/*  Symbolic ID for instance variable names  */
static ID s_ID_track, s_ID_eot_selected;

/*
 *  call-seq:
 *     MREventSet.new([track,] arg1, arg2, ...)
 *     MREventSet.new([track,] arg1, arg2, ...) { |n| ... }
 *
 *  Create a new eventset. Arg1, arg2,... and block are handled as in MRPointSet.
 *  If track is given, then the created eventset is associated with the track.
 *  Otherwise, it is not associated with any track.
 */
static VALUE
s_MREventSet_Initialize(int argc, VALUE *argv, VALUE self)
{
	VALUE tval;
	if (argc > 0 && rb_obj_is_kind_of(argv[0], rb_cMRTrack)) {
		tval = argv[0];
		argv++;
		argc--;
	} else tval = Qnil;
	s_MRPointSet_Initialize(argc, argv, self);
	rb_ivar_set(self, s_ID_track, tval);
	rb_ivar_set(self, s_ID_eot_selected, Qfalse);
	return Qnil;
}

VALUE
MREventSetValueFromPointSetAndTrackInfo(MDPointSet *pset, MDTrack *track, void *myDocument, int isEndOfTrackSelected)
{
	VALUE val, tval;
	MDPointSet *pset2;
	MyDocument *doc = (MyDocument *)myDocument;
	tval = MRTrackValueFromTrackInfo(track, doc, -1);
	val = MRPointSet_Alloc(rb_cMREventSet);
	s_MREventSet_Initialize(1, &tval, val);
	pset2 = MDPointSetFromValue(val);
	MDPointSetCopy(pset2, pset);
	if (isEndOfTrackSelected)
		rb_ivar_set(val, s_ID_eot_selected, Qtrue);
	return val;
}

/*
 *  call-seq:
 *     MREventSet.track
 *
 *  Accessor (getter) function for @track.
 */
VALUE
MREventSet_Track(VALUE self)
{
	return rb_ivar_get(self, s_ID_track);
}

/*
 *  call-seq:
 *     MREventSet.eot_selected
 *
 *  Accessor (getter) function for @eot_selected.
 */
VALUE
MREventSet_EOTSelected(VALUE self)
{
	return rb_ivar_get(self, s_ID_eot_selected);
}

/*
 *  call-seq:
 *     MREventSet.track=
 *
 *  Accessor (setter) function for @track.
 */
VALUE
MREventSet_SetTrack(VALUE self, VALUE val)
{
	if (!rb_obj_is_kind_of(val, rb_cMRTrack))
		rb_raise(rb_eTypeError, "track value must be Track type");
	rb_ivar_set(self, s_ID_track, val);
	return val;
}

/*
 *  call-seq:
 *     MREventSet.eot_selected=
 *
 *  Accessor (setter) function for @eot_selected.
 */
VALUE
MREventSet_SetEOTSelected(VALUE self, VALUE val)
{
	rb_ivar_set(self, s_ID_eot_selected, val);
	return val;
}

static VALUE
s_MREventSet_Pointer(VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	return MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
}

/*
 *  call-seq:
 *     MREventSet.each { |pt| ... }
 *
 *  Iterate the block for each event. Pt is a Pointer value, and the same object
 *  is given for all block call.
 */
static VALUE
s_MREventSet_Each(VALUE self)
{
	MDPointer *pt;
	MDPointSet *pset;
	long idx;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	pset = MDPointSetFromValue(self);
	idx = -1;
	while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
		rb_yield(pval);
	}
	return self;
}

/*
 *  call-seq:
 *     MREventSet.reverse_each { |pt| ... }
 *
 *  Iterate the block backward for each event. Pt is a Pointer value, and the same object
 *  is given for all block call.
 */
static VALUE
s_MREventSet_ReverseEach(VALUE self)
{
	MDPointer *pt;
	MDPointSet *pset;
	long idx;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	MDPointerSetPosition(pt, kMDMaxPosition);
	pset = MDPointSetFromValue(self);
	idx = -1;
	while (MDPointerBackwardWithPointSet(pt, pset, &idx) != NULL) {
		rb_yield(pval);
	}
	return self;
}

/*
 *  call-seq:
 *     MREventSet.each_with_index { |pt,i| ... }
 *
 *  Iterate the block for each event. Pt is a Pointer value, and i is the index
 *  of the event within the event set.
 */
static VALUE
s_MREventSet_EachWithIndex(VALUE self)
{
	MDPointer *pt;
	MDPointSet *pset;
	long idx;
	int n;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	pset = MDPointSetFromValue(self);
	idx = -1;
	n = 0;
	while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
		rb_yield_values(2, pval, INT2NUM(n));
		n++;
	}
	return self;
}

/*
 *  call-seq:
 *     MREventSet.reverse_each_with_index { |pt,i| ... }
 *
 *  Iterate the block backward for each event. Pt is a Pointer value, and i is the index
 *  of the event within the event set (going downward from self.length-1 to 0)
 */
static VALUE
s_MREventSet_ReverseEachWithIndex(VALUE self)
{
	MDPointer *pt;
	MDPointSet *pset;
	long idx;
	int n;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	MDPointerSetPosition(pt, kMDMaxPosition);
	pset = MDPointSetFromValue(self);
	idx = -1;
	n = MDPointSetGetCount(pset) - 1;
	while (MDPointerBackwardWithPointSet(pt, pset, &idx) != NULL) {
		rb_yield_values(2, pval, NUM2INT(n));
		n--;
	}
	return self;
}

static VALUE
s_MREventSet_Select_sub(VALUE self, int reject)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, pval;
	MDPointer *pt;
	MDPointSet *pset, *pset2;
	long idx;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
	pt = MDPointerFromMRPointerValue(pval);
	pset = MDPointSetFromValue(self);
	pset2 = MDPointSetNew();
	idx = -1;
	while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
		if (RTEST(rb_yield(pval)))
			MDPointSetAdd(pset2, MDPointerGetPosition(pt), 1);
	}
	if (reject) {
		MDPointSetRemovePointSet(pset, pset2);
		if (MDPointSetGetCount(pset2) == 0)
			tval = Qnil;
		else tval = self;
	} else {
		tval = MREventSetValueFromPointSetAndTrackInfo(pset2, ip->track, ip->doc, 0);
	}
	MDPointSetRelease(pset2);
	return tval;
}

/*
 *  call-seq:
 *     MREventSet.select { |pt| ... }
 *
 *  Create a new event set from those for which the block returns true.
 */
static VALUE
s_MREventSet_Select(VALUE self)
{
	return s_MREventSet_Select_sub(self, 0);
}

/*
 *  call-seq:
 *     MREventSet.reject! { |pt| ... }
 *
 *  Remove those events for which the block returns true. Returns nil if
 *  no events were removed, otherwise returns self.
 */
static VALUE
s_MREventSet_Reject(VALUE self)
{
	return s_MREventSet_Select_sub(self, 1);
}

/*
 *  call-seq:
 *     MREventSet.modify_tick(num)
 *     MREventSet.modify_tick(array)
 *     MREventSet.modify_tick { |pt| }
 *
 *  Modify the tick of the specified events. In the first form, the ticks are shifted 
 *  by the given number. In the second form, the new tick values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the third form, the new tick values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyTick(int argc, VALUE *argv, VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval;
	MDPointSet *pset;
	MDPointSetObject *psobj;
	id theData;
	int n1, n2;
	MDTickType *tickp;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pset = MDPointSetFromValue(self);
	n2 = MDPointSetGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[MDPointSetObject alloc] initWithMDPointSet: pset] autorelease];
	rb_scan_args(argc, argv, "01", &nval);
	if (nval == Qnil) {
		/*  The new tick values are given by the block  */
		VALUE pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
		MDPointer *pt = MDPointerFromMRPointerValue(pval);
		long idx = -1;
		n1 = 0;
		theData = [NSMutableData dataWithLength: sizeof(MDTickType) * n2];
		tickp = (MDTickType *)[theData mutableBytes];		
		while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
			tickp[n1] = NUM2DBL(rb_yield(pval));
			n1++;
		}
		[MyDocument modifyTick: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet destinationPositions: nil];
		return self;
	} else if (rb_obj_is_kind_of(nval, rb_cNumeric)) {
		theData = [NSNumber numberWithInt: NUM2INT(rb_Integer(nval))];
		[MyDocument modifyTick: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifyAdd destinationPositions: nil];
		return self;
	} else {
		VALUE *nvalp;
		int i;
		nval = rb_ary_to_ary(nval);
		n1 = RARRAY_LEN(nval);
		if (n1 == 0)
			return self;
		theData = [NSMutableData dataWithLength: sizeof(MDTickType) * n2];
		tickp = (MDTickType *)[theData mutableBytes];
		nvalp = RARRAY_PTR(nval);
		for (i = 0; i < n1 && i < n2; i++) {
			tickp[i] = NUM2INT(rb_Integer(nvalp[i]));
		}
		while (i < n2) {
			tickp[i] = tickp[n1 - 1];
			i++;
		}
		[MyDocument modifyTick: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet destinationPositions: nil];
		return self;
	}
}

/*
 *  call-seq:
 *     MREventSet.modify_code(num)
 *     MREventSet.modify_code(array)
 *     MREventSet.modify_code { |pt| }
 *
 *  Modify the code of the specified events. In the first form, the codes are shifted by num
 *  for all specified events. In the second form, the new code values are taken from the array.
 *  In the third form, the new code values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyCode(int argc, VALUE *argv, VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval;
	int n1, n2;
	MDPointSetObject *psobj;
	MDPointSet *pset;
	id theData;
	short *shortp;
	VALUE *nvalp;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	rb_scan_args(argc, argv, "01", &nval);
	pset = MDPointSetFromValue(self);
	n2 = MDPointSetGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[MDPointSetObject alloc] initWithMDPointSet: pset] autorelease];
	if (nval == Qnil) {
		VALUE pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
		MDPointer *pt = MDPointerFromMRPointerValue(pval);
		long idx = -1;
		n1 = 0;
		theData = [NSMutableData dataWithLength: sizeof(short) * n2];
		shortp = (short *)[theData mutableBytes];		
		while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
			shortp[n1] = NUM2INT(rb_yield(pval));
			n1++;
		}
		[MyDocument modifyCodes: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	} else if (rb_obj_is_kind_of(nval, rb_cNumeric)) {
		theData = [NSNumber numberWithInt: NUM2INT(rb_Integer(nval))];
		[MyDocument modifyCodes: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifyAdd];
		return self;
	} else {
		int i;
		nval = rb_ary_to_ary(nval);
		n1 = RARRAY_LEN(nval);
		if (n1 == 0)
			return self;
		theData = [NSMutableData dataWithLength: sizeof(short) * n2];
		shortp = (short *)[theData mutableBytes];
		nvalp = RARRAY_PTR(nval);
		for (i = 0; i < n1 && i < n2; i++) {
			shortp[i] = NUM2INT(rb_Integer(nvalp[i]));
		}
		while (i < n2) {
			shortp[i] = shortp[n1 - 1];
			i++;
		}
		[MyDocument modifyCodes: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	}
}

static VALUE
s_MREventSet_ModifyDataSub(int argc, VALUE *argv, VALUE self, int kind)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval, pval;
	int i, n1, n2, n3;
	MDPointSetObject *psobj;
	MDPointSet *pset;
	id theData;
	float *floatp;
	VALUE *nvalp;
	MDPointer *pt;
	MDEvent *ep;
	long idx;

	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	rb_scan_args(argc, argv, "01", &nval);
	pset = MDPointSetFromValue(self);
	n2 = MDPointSetGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[MDPointSetObject alloc] initWithMDPointSet: pset] autorelease];
	
	pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
	pt = MDPointerFromMRPointerValue(pval);
	idx = -1;
	
	if (kind < 0 || kind == kMDEventNull) {
		/*  Specify the kind from the selected event  */
		kind = -1;
		while ((ep = MDPointerForwardWithPointSet(pt, pset, &idx)) != NULL) {
			char name1[32], name2[32];
			if (kind == -1) {
				kind = MDGetKind(ep);
				MDEventToKindString(ep, name1, sizeof name1);
			} else if (kind != MDGetKind(ep)) {
				MDEventToKindString(ep, name2, sizeof name2);
				rb_raise(rb_eStandardError, "event at %ld is of different kind (%s) from the first event (%s)", (long)MDPointerGetPosition(pt), name1, name2);
			}
		}
	}
	MDPointerSetPosition(pt, -1);
	
	n1 = 0;
	if (nval == Qnil)
		n3 = 0; /* block */
	else if (rb_obj_is_kind_of(nval, rb_cString) || rb_obj_is_kind_of(nval, rb_cNumeric))
		n3 = 1; /* single value */
	else if (rb_obj_is_kind_of(nval, rb_cArray)) {
		n1 = RARRAY_LEN(nval);
		nvalp = RARRAY_PTR(nval);
		if ((kind == kMDEventTimeSignature && n1 >= 2 && rb_obj_is_kind_of(nvalp[0], rb_cNumeric))
			|| (kind == kMDEventSMPTE && n1 == 5 && rb_obj_is_kind_of(nvalp[0], rb_cNumeric))
			|| (kind == kMDEventKey && n1 >= 2 && rb_obj_is_kind_of(nvalp[0], rb_cString) && rb_obj_is_kind_of(nvalp[1], rb_cNumeric)))
			n3 = 1;
		else n3 = 2; /* array */
	} else {
		nval = rb_ary_to_ary(nval);
		n1 = RARRAY_LEN(nval);
		nvalp = RARRAY_PTR(nval);
		n3 = 2; /* array */
	}
	
	if (n3 == 2 && n1 == 0)
		return self;
	
	if (kind == kMDEventMetaText || kind == kMDEventMetaMessage || kind == kMDEventSysex ||
		kind == kMDEventSysexCont || kind == kMDEventSMPTE || kind == kMDEventTimeSignature ||
		kind == kMDEventKey) {
		ID mid = rb_intern("data=");
		idx = -1;
		i = 0;
		while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
			VALUE dval;
			if (n3 == 0)
				dval = rb_yield(pval);
			else if (n3 == 2) {
				if (i < n1)
					dval = nvalp[i];
				else
					dval = nvalp[n1 - 1];
			}
			else dval = nval;
			rb_funcall(pval, mid, 1, dval);
			i++;
		}
		return self;
	}
	
	if (n3 == 0) {
		idx = -1;
		i = 0;
		theData = [NSMutableData dataWithLength: sizeof(float) * n2];
		floatp = (float *)[theData mutableBytes];
		while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
			floatp[i] = NUM2DBL(rb_Float(rb_yield(pval)));
			i++;
		}
		[MyDocument modifyData: theData forEventKind: kind ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	} else if (n3 == 1) {
		theData = [NSNumber numberWithFloat: NUM2DBL(rb_Float(nval))];
		[MyDocument modifyData: theData forEventKind: kind ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifyAdd];
		return self;
	} else {
		theData = [NSMutableData dataWithLength: sizeof(float) * n2];
		floatp = (float *)[theData mutableBytes];
		for (i = 0; i < n1 && i < n2; n1++) {
			floatp[i] = NUM2DBL(rb_Float(nvalp[i]));
		}
		while (i < n2) {
			floatp[i] = floatp[n1 - 1];
		}
		[MyDocument modifyData: theData forEventKind: kind ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	}
}

/*
 *  call-seq:
 *     MREventSet.modify_data(dat)
 *     MREventSet.modify_data(val)
 *     MREventSet.modify_data { |pt| }
 *
 *  Modify the "data" of the specified events. All specified events must be of the same
 *  kind. In the first form, the data of the events are set to dat.
 *  In the second form, the new data values are taken from the array.
 *  In the third form, the new data values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 *  If pointset is nil, the current selection is used.
 */
static VALUE
s_MREventSet_ModifyData(int argc, VALUE *argv, VALUE self)
{
	return s_MREventSet_ModifyDataSub(argc, argv, self, -1);
}

/*
 *  call-seq:
 *     MREventSet.modify_velocity(num)
 *     MREventSet.modify_velocity(val)
 *     MREventSet.modify_velocity { |pt, i| }
 *
 *  Modify the velocities of the specified events. All specified events must be note events.
 *  In the first form, the velocity of the events are set to num.
 *  In the second form, the new velocity values are taken from the array.
 *  In the third form, the new velocity values are given by the block. The block arguments
 *  are the event pointer and the index within the pointset.
 */
static VALUE
s_MREventSet_ModifyVelocity(int argc, VALUE *argv, VALUE self)
{
	return s_MREventSet_ModifyDataSub(argc, argv, self, kMDEventNote);
}

/*
 *  call-seq:
 *     MREventSet.modify_release_velocity(num)
 *     MREventSet.modify_release_velocity(val)
 *     MREventSet.modify_release_velocity { |pt, i| }
 *
 *  Modify the release velocities of the specified events. All specified events must be note events.
 *  In the first form, the release velocity of the events are set to num.
 *  In the second form, the new release velocity values are taken from the array.
 *  In the third form, the new release velocity values are given by the block. The block arguments
 *  are the event pointer and the index within the pointset.
 */
static VALUE
s_MREventSet_ModifyReleaseVelocity(int argc, VALUE *argv, VALUE self)
{
	return s_MREventSet_ModifyDataSub(argc, argv, self, kMDEventInternalNoteOff);
}

/*
 *  call-seq:
 *     MREventSet.modify_duration(num)
 *     MREventSet.modify_duration(array)
 *     MREventSet.modify_duration { |pt, i| }
 *
 *  Modify the durations of the specified events. In the first form, the durations are 
 *  incremented/decremented by num for all specified events. In the second form, the 
 *  new duration values are taken from the array.
 *  In the third form, the new duration values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 *  If pointset is nil, the current selection is used.
 */
static VALUE
s_MREventSet_ModifyDuration(int argc, VALUE *argv, VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval;
	int n1, n2;
	MDPointSetObject *psobj;
	MDPointSet *pset;
	id theData;
	MDTickType *tickp;
	VALUE *nvalp;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	rb_scan_args(argc, argv, "01", &nval);
	pset = MDPointSetFromValue(self);
	n2 = MDPointSetGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[MDPointSetObject alloc] initWithMDPointSet: pset] autorelease];
	if (nval == Qnil) {
		VALUE pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
		MDPointer *pt = MDPointerFromMRPointerValue(pval);
		long idx = -1;
		n1 = 0;
		theData = [NSMutableData dataWithLength: sizeof(MDTickType) * n2];
		tickp = (MDTickType *)[theData mutableBytes];		
		while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
			tickp[n1] = NUM2INT(rb_yield(pval));
			n1++;
		}
		[MyDocument modifyDurations: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	} else if (rb_obj_is_kind_of(nval, rb_cNumeric)) {
		theData = [NSNumber numberWithLong: (long)(NUM2INT(rb_Integer(nval)))];
		[MyDocument modifyDurations: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifyAdd];
		return self;
	} else {
		int i;
		nval = rb_ary_to_ary(nval);
		n1 = RARRAY_LEN(nval);
		if (n1 == 0)
			return self;
		theData = [NSMutableData dataWithLength: sizeof(MDTickType) * n2];
		tickp = (MDTickType *)[theData mutableBytes];
		nvalp = RARRAY_PTR(nval);
		for (i = 0; i < n2 && i < n2; i++) {
			tickp[i] = NUM2INT(rb_Integer(nvalp[i]));
		}
		while (i < n2) {
			tickp[i] = tickp[n1 - 1];
			i++;
		}
		[MyDocument modifyDurations: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	}
}

#pragma mark ====== Class definition (external entry) ======

void
MREventSetInitClass(void)
{	
	/*  class MRPointSet  */
	rb_cMRPointSet = rb_define_class("PointSet", rb_cObject);
	rb_include_module(rb_cMRPointSet, rb_mEnumerable);
	rb_define_alloc_func(rb_cMRPointSet, MRPointSet_Alloc);
	rb_define_method(rb_cMRPointSet, "clear", s_MRPointSet_Clear, 0);
	rb_define_method(rb_cMRPointSet, "initialize", s_MRPointSet_Initialize, -1);
	rb_define_method(rb_cMRPointSet, "initialize_copy", s_MRPointSet_InitializeCopy, 1);
	rb_define_method(rb_cMRPointSet, "length", s_MRPointSet_Length, 0);
	rb_define_alias(rb_cMRPointSet, "size", "length");
	rb_define_method(rb_cMRPointSet, "member?", s_MRPointSet_MemberP, 1);
	rb_define_alias(rb_cMRPointSet, "include?", "member?");
	rb_define_method(rb_cMRPointSet, "each", s_MRPointSet_Each, 0);
	rb_define_method(rb_cMRPointSet, "[]", s_MRPointSet_ElementAtIndex, 1);
	rb_define_method(rb_cMRPointSet, "add", s_MRPointSet_Add, 1);
	rb_define_alias(rb_cMRPointSet, "<<", "add");
	rb_define_method(rb_cMRPointSet, "delete", s_MRPointSet_Delete, 1);
	rb_define_method(rb_cMRPointSet, "reverse", s_MRPointSet_Reverse, 1);
	rb_define_method(rb_cMRPointSet, "merge", s_MRPointSet_Add, 1);
	rb_define_method(rb_cMRPointSet, "subtract", s_MRPointSet_Delete, 1);
	rb_define_method(rb_cMRPointSet, "union", s_MRPointSet_Union, 1);
	rb_define_method(rb_cMRPointSet, "difference", s_MRPointSet_Difference, 1);
	rb_define_method(rb_cMRPointSet, "intersection", s_MRPointSet_Intersection, 1);
	rb_define_method(rb_cMRPointSet, "sym_difference", s_MRPointSet_SymDifference, 1);
	rb_define_method(rb_cMRPointSet, "convolute", s_MRPointSet_Convolute, 1);
	rb_define_method(rb_cMRPointSet, "deconvolute", s_MRPointSet_Deconvolute, 1);
	rb_define_method(rb_cMRPointSet, "offset", s_MRPointSet_Offset, 1);
	rb_define_alias(rb_cMRPointSet, "+", "union");
	rb_define_alias(rb_cMRPointSet, "|", "union");
	rb_define_alias(rb_cMRPointSet, "-", "difference");
	rb_define_alias(rb_cMRPointSet, "&", "intersection");
	rb_define_alias(rb_cMRPointSet, "^", "sym_difference");
	rb_define_method(rb_cMRPointSet, "range_at", s_MRPointSet_RangeAt, 1);
	rb_define_method(rb_cMRPointSet, "inspect", s_MRPointSet_Inspect, 0);
	rb_define_alias(rb_cMRPointSet, "to_s", "inspect");
	rb_define_singleton_method(rb_cMRPointSet, "[]", s_MRPointSet_Create, -1);

	/*  Class MREventSet: it is an MREventSet with an associated Track  */
	rb_cMREventSet = rb_define_class("EventSet", rb_cMRPointSet);
	rb_define_method(rb_cMREventSet, "initialize", s_MREventSet_Initialize, -1);
	rb_define_method(rb_cMREventSet, "track", MREventSet_Track, 0);
	rb_define_method(rb_cMREventSet, "eot_selected", MREventSet_EOTSelected, 0);
	rb_define_method(rb_cMREventSet, "track=", MREventSet_SetTrack, 1);
	rb_define_method(rb_cMREventSet, "eot_selected=", MREventSet_SetEOTSelected, 1);
	rb_define_method(rb_cMREventSet, "each", s_MREventSet_Each, 0);
	rb_define_method(rb_cMREventSet, "reverse_each", s_MREventSet_ReverseEach, 0);
	rb_define_method(rb_cMREventSet, "each_with_index", s_MREventSet_EachWithIndex, 0);
	rb_define_method(rb_cMREventSet, "reverse_each_with_index", s_MREventSet_ReverseEachWithIndex, 0);
	rb_define_method(rb_cMREventSet, "select", s_MREventSet_Select, 0);
	rb_define_method(rb_cMREventSet, "reject!", s_MREventSet_Reject, 0);
	rb_define_method(rb_cMREventSet, "modify_tick", s_MREventSet_ModifyTick, -1);
	rb_define_method(rb_cMREventSet, "modify_code", s_MREventSet_ModifyCode, -1);
	rb_define_method(rb_cMREventSet, "modify_data", s_MREventSet_ModifyData, -1);
	rb_define_method(rb_cMREventSet, "modify_velocity", s_MREventSet_ModifyVelocity, -1);
	rb_define_method(rb_cMREventSet, "modify_release_velocity", s_MREventSet_ModifyReleaseVelocity, -1);
	rb_define_method(rb_cMREventSet, "modify_duration", s_MREventSet_ModifyDuration, -1);

	s_ID_track = rb_intern("@track");
	s_ID_eot_selected = rb_intern("@eot_selected");
}
