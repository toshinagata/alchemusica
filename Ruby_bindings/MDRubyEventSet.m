/*
 *  MDRubyEventSet.m
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 09/01/24.
 *  Copyright 2009-2017 Toshi Nagata. All rights reserved.
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

/*  The MRPointSet class is dependent only on IntGroup  */

VALUE rb_cIntGroup;

IntGroup *
IntGroupFromValue(VALUE val)
{
	IntGroup *pset;
	if (!rb_obj_is_kind_of(val, rb_cIntGroup))
		val = rb_funcall(rb_cIntGroup, rb_intern("new"), 1, val);
	Data_Get_Struct(val, IntGroup, pset);
	return pset;
}

VALUE
ValueFromIntGroup(IntGroup *pset)
{
	if (pset == NULL)
		return Qnil;
	IntGroupRetain(pset);
    return Data_Wrap_Struct(rb_cIntGroup, 0, (void (*)(void *))IntGroupRelease, pset);
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
		rb_raise(rb_eStandardError, "%s error occurred during IntGroup operation", s);
	}
}

/*  Allocator  */
VALUE
MRPointSet_Alloc(VALUE klass)
{
	IntGroup *pset = IntGroupNew();
    return Data_Wrap_Struct(klass, 0, (void (*)(void *))IntGroupRelease, pset);
}

/*  Iterator block for initializer  */
static VALUE
s_MRPointSet_Initialize_i(VALUE val, VALUE pset1)
{
	MRPointSet_RaiseIfError(IntGroupAdd((IntGroup *)pset1, NUM2INT(val), 1));
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
	IntGroup *pset1;
	Data_Get_Struct(self, IntGroup, pset1);
	while (argc-- > 0) {
		VALUE arg = *argv++;
		int type = TYPE(arg);
		if (rb_obj_is_kind_of(arg, rb_cIntGroup))
			rb_funcall(rb_cIntGroup, rb_intern("merge"), 1, arg);
		else if (rb_obj_is_kind_of(arg, rb_cRange)) {
			int sp, ep;
			sp = NUM2INT(rb_funcall(arg, rb_intern("begin"), 0));
			ep = NUM2INT(rb_funcall(arg, rb_intern("end"), 0));
			if (RTEST(rb_funcall(arg, rb_intern("exclude_end?"), 0)))
				ep--;
			if (ep >= sp)
				MRPointSet_RaiseIfError(IntGroupAdd(pset1, sp, ep - sp + 1));
		} else if (rb_respond_to(arg, rb_intern("each")) && type != T_STRING)
			rb_iterate(rb_each, arg, s_MRPointSet_Initialize_i, (VALUE)pset1);
		else
			MRPointSet_RaiseIfError(IntGroupAdd(pset1, NUM2INT(arg), 1));
	}
	if (rb_block_given_p()) {
		IntGroup *pset2 = IntGroupNew();
		int i, n;
		for (i = 0; (n = IntGroupGetNthPoint(pset1, i)) >= 0; i++) {
			n = NUM2INT(rb_yield(INT2NUM(n)));
			if (n >= 0)
				MRPointSet_RaiseIfError(IntGroupAdd(pset2, n, 1));
		}
		MRPointSet_RaiseIfError(IntGroupCopy(pset1, pset2));
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
	IntGroup *pset;
	Data_Get_Struct(self, IntGroup, pset);
	IntGroupClear(pset);
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
	IntGroup *pset1, *pset2;
	Data_Get_Struct(self, IntGroup, pset1);
	if (!rb_obj_is_kind_of(val, rb_cIntGroup))
		rb_raise(rb_eTypeError, "IntGroup instance is expected");
    Data_Get_Struct(val, IntGroup, pset2);
	IntGroupCopy(pset1, pset2);
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
	IntGroup *pset;
	Data_Get_Struct(self, IntGroup, pset);
	return INT2NUM(IntGroupGetCount(pset));
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
	IntGroup *pset;
	int n = NUM2INT(val);
	Data_Get_Struct(self, IntGroup, pset);
	return (IntGroupLookup(pset, n, NULL) ? Qtrue : Qfalse);
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
	IntGroup *pset;
	int n;
	int index = NUM2INT(rb_Integer(val));
	Data_Get_Struct(self, IntGroup, pset);
	n = IntGroupGetNthPoint(pset, index);
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
	IntGroup *pset;
	int i, j, sp, ep;
	Data_Get_Struct(self, IntGroup, pset);
	for (i = 0; (sp = IntGroupGetStartPoint(pset, i)) >= 0; i++) {
		ep = IntGroupGetEndPoint(pset, i);
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
	IntGroup *pset, *pset2;
    if (OBJ_FROZEN(self))
		rb_error_frozen("IntGroup");
	Data_Get_Struct(self, IntGroup, pset);
	if (rb_obj_is_kind_of(val, rb_cNumeric)) {
		int n = NUM2INT(rb_Integer(val));
		if (n < 0)
			rb_raise(rb_eRangeError, "the integer group can contain only non-negative values");
		IntGroupAdd(pset, n, 1);
	} else {
		pset2 = IntGroupFromValue(val);
		IntGroupAddIntGroup(pset, pset2);
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
	IntGroup *pset, *pset2;
    if (OBJ_FROZEN(self))
		rb_error_frozen("IntGroup");
	Data_Get_Struct(self, IntGroup, pset);
	if (rb_obj_is_kind_of(val, rb_cNumeric)) {
		int n = NUM2INT(rb_Integer(val));
		if (n >= 0 && IntGroupLookup(pset, n, NULL))
			IntGroupRemove(pset, n, 1);
	} else {
		pset2 = IntGroupFromValue(val);
		IntGroupRemoveIntGroup(pset, pset2);
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
	IntGroup *pset, *pset2;
    if (OBJ_FROZEN(self))
		rb_error_frozen("IntGroup");
	Data_Get_Struct(self, IntGroup, pset);
	if (rb_obj_is_kind_of(val, rb_cNumeric)) {
		int n = NUM2INT(rb_Integer(val));
		if (n >= 0 && IntGroupLookup(pset, n, NULL))
			IntGroupReverse(pset, n, 1);
	} else {
		pset2 = IntGroupFromValue(val);
		IntGroupReverseIntGroup(pset, pset2);
	}
	return self;
}

static VALUE
s_MRPointSet_Binary(VALUE self, VALUE val, int (*func)(const IntGroup *, const IntGroup *, IntGroup *))
{
	IntGroup *pset1, *pset2, *pset3;
	VALUE retval;
	Data_Get_Struct(self, IntGroup, pset1);
	pset2 = IntGroupFromValue(val);
/*	retval = MRPointSet_Alloc(rb_cIntGroup); */
	retval = rb_obj_dup(self); /* the return value will have the same class as self  */
	Data_Get_Struct(retval, IntGroup, pset3);
	IntGroupClear(pset3);
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
	return s_MRPointSet_Binary(self, val, IntGroupUnion);
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
	return s_MRPointSet_Binary(self, val, IntGroupIntersect);
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
	return s_MRPointSet_Binary(self, val, IntGroupDifference);
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
	return s_MRPointSet_Binary(self, val, IntGroupXor);
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
	return s_MRPointSet_Binary(self, val, IntGroupConvolute);
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
	return s_MRPointSet_Binary(self, val, IntGroupDeconvolute);
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
	IntGroup *pset;
	int n = NUM2INT(val);
	int sp, ep;
	Data_Get_Struct(self, IntGroup, pset);
	sp = IntGroupGetStartPoint(pset, n);
	if (sp < 0)
		return Qnil;
	ep = IntGroupGetEndPoint(pset, n) - 1;
	return rb_funcall(rb_cRange, rb_intern("new"), 2, INT2NUM(sp), INT2NUM(ep));
}

/*
static VALUE
s_MRPointSet_Merge(VALUE self, VALUE val)
{
	IntGroup *pset1, *pset2;
	int i, sp, interval;
    if (OBJ_FROZEN(self))
		rb_error_frozen("IntGroup");
	Data_Get_Struct(self, IntGroup, pset1);
	pset2 = IntGroupFromValue(val);
	for (i = 0; (sp = IntGroupGetStartPoint(pset2, i)) >= 0; i++) {
		interval = IntGroupGetInterval(pset2, i);
		MRPointSet_RaiseIfError(IntGroupAdd(pset1, sp, interval));
	}
	return self;
}

static VALUE
s_MRPointSet_Subtract(VALUE self, VALUE val)
{
	IntGroup *pset1, *pset2;
	int i, sp, interval;
    if (OBJ_FROZEN(self))
		rb_error_frozen("IntGroup");
	Data_Get_Struct(self, IntGroup, pset1);
	pset2 = IntGroupFromValue(val);
	for (i = 0; (sp = IntGroupGetStartPoint(pset2, i)) >= 0; i++) {
		interval = IntGroupGetInterval(pset2, i);
		MRPointSet_RaiseIfError(IntGroupRemove(pset1, sp, interval));
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
	IntGroup *pset1, *pset2;
	int iofs;
	VALUE val;
	Data_Get_Struct(self, IntGroup, pset1);
	pset2 = IntGroupNew();
	if (pset2 == NULL || IntGroupCopy(pset2, pset1) != kMDNoError)
		rb_raise(rb_eTypeError, "Cannot duplicate IntGroup");
	iofs = NUM2INT(ofs);
	if (IntGroupOffset(pset2, iofs) != 0)
		rb_raise(rb_eRangeError, "Bad offset %d", iofs);
	val = ValueFromIntGroup(pset2);
	IntGroupRelease(pset2);
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
	IntGroup *pset;
	char buf[64];
	VALUE klass = CLASS_OF(self);
	VALUE val = rb_funcall(klass, rb_intern("name"), 0);
	Data_Get_Struct(self, IntGroup, pset);
	rb_str_cat(val, "[", 1);
	for (i = 0; (sp = IntGroupGetStartPoint(pset, i)) >= 0; i++) {
		if (i > 0)
			rb_str_cat(val, ", ", 2);
		ep = IntGroupGetEndPoint(pset, i);
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
MREventSetValueFromIntGroupAndTrackInfo(IntGroup *pset, MDTrack *track, void *myDocument, int isEndOfTrackSelected)
{
	VALUE val, tval;
	IntGroup *pset2;
	MyDocument *doc = (MyDocument *)myDocument;
	tval = MRTrackValueFromTrackInfo(track, doc, -1);
	val = MRPointSet_Alloc(rb_cMREventSet);
	s_MREventSet_Initialize(1, &tval, val);
	pset2 = IntGroupFromValue(val);
	IntGroupCopy(pset2, pset);
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
	IntGroup *pset;
	int idx;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	pset = IntGroupFromValue(self);
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
	IntGroup *pset;
	int idx;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	MDPointerSetPosition(pt, kMDMaxPosition);
	pset = IntGroupFromValue(self);
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
	IntGroup *pset;
	int idx;
	int n;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	pset = IntGroupFromValue(self);
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
	IntGroup *pset;
	int idx;
	int n;
	VALUE pval = s_MREventSet_Pointer(self);
	pt = MDPointerFromMRPointerValue(pval);
	MDPointerSetPosition(pt, kMDMaxPosition);
	pset = IntGroupFromValue(self);
	idx = -1;
	n = IntGroupGetCount(pset) - 1;
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
	IntGroup *pset, *pset2;
	int idx;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
	pt = MDPointerFromMRPointerValue(pval);
	pset = IntGroupFromValue(self);
	pset2 = IntGroupNew();
	idx = -1;
	while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
		if (RTEST(rb_yield(pval)))
			IntGroupAdd(pset2, MDPointerGetPosition(pt), 1);
	}
	if (reject) {
		IntGroupRemoveIntGroup(pset, pset2);
		if (IntGroupGetCount(pset2) == 0)
			tval = Qnil;
		else tval = self;
	} else {
		tval = MREventSetValueFromIntGroupAndTrackInfo(pset2, ip->track, ip->doc, 0);
	}
	IntGroupRelease(pset2);
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
 *     MREventSet.modify_tick(op, num)  #  op is either "=", "+", or "*"
 *     MREventSet.modify_tick(num)      #  same as ("+", num)
 *     MREventSet.modify_tick(array)
 *     MREventSet.modify_tick { |pt| }
 *
 *  Modify the tick of the specified events.
 *  In the first form, the ticks are set, shift, or multiplied by the argument.
 *  The second form is equivalent to modify_tick("+", num) (i.e. shifted by the argument)
 *  In the third form, the new tick values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the fourth form, the new tick values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyTick(int argc, VALUE *argv, VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval;
	IntGroup *pset;
	IntGroupObject *psobj;
	id theData;
	int n1, n2, mode;
	MDTickType *tickp;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pset = IntGroupFromValue(self);
	n2 = IntGroupGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[IntGroupObject alloc] initWithMDPointSet: pset] autorelease];
	mode = MyDocumentModifyAdd;
	if (argc >= 1) {
		nval = argv[0];
		if (rb_obj_is_kind_of(nval, rb_cString)) {
			if (argc == 1)
				rb_raise(rb_eStandardError, "Modify operation requires a single numeric argument");
			n1 = RSTRING_PTR(nval)[0];
			if (n1 == '=')
				mode = MyDocumentModifyAdd;
			else if (n1 == '*')
				mode = MyDocumentModifyMultiply;
			else if (n1 != '+')
				rb_raise(rb_eStandardError, "Modify operation should be either '=', '+' or '*'");
			nval = argv[1];
			if (mode != MyDocumentModifySet && !rb_obj_is_kind_of(nval, rb_cNumeric))
				rb_raise(rb_eStandardError, "Add or multiply operation requires a single numeric argument");
		}
	} else nval = Qnil;
	if (nval == Qnil) {
		/*  The new tick values are given by the block  */
		VALUE pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
		MDPointer *pt = MDPointerFromMRPointerValue(pval);
		int idx = -1;
		n1 = 0;
		theData = [NSMutableData dataWithLength: sizeof(MDTickType) * n2];
		tickp = (MDTickType *)[theData mutableBytes];		
		while (MDPointerForwardWithPointSet(pt, pset, &idx) != NULL) {
			tickp[n1] = (MDTickType)NUM2DBL(rb_yield(pval));
			n1++;
		}
        [MyDocument modifyTick: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet destinationPositions: nil setSelection: YES];
		return self;
	} else if (rb_obj_is_kind_of(nval, rb_cNumeric)) {
		if (mode == MyDocumentModifyMultiply)
			theData = [NSNumber numberWithFloat: (float)NUM2DBL(rb_Float(nval))];
		else
			theData = [NSNumber numberWithInt: NUM2INT(rb_Integer(nval))];
        [MyDocument modifyTick: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: mode destinationPositions: nil setSelection: YES];
		return self;
	} else {
		VALUE *nvalp;
		int i;
		nval = rb_ary_to_ary(nval);
		n1 = (int)RARRAY_LEN(nval);
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
        [MyDocument modifyTick: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet destinationPositions: nil setSelection: YES];
		return self;
	}
}

/*
 *  call-seq:
 *     MREventSet.modify_code(op, num)  #  op is either "=", "+", or "*"
 *     MREventSet.modify_code(num)      #  same as ("+", num)
 *     MREventSet.modify_code(array)
 *     MREventSet.modify_code { |pt| }
 *
 *  Modify the code of the specified events.
 *  In the first form, the codes are set, shift, or multiplied by the argument.
 *  The second form is equivalent to modify_code("+", num) (i.e. shifted by the argument)
 *  In the third form, the new code values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the fourth form, the new code values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyCode(int argc, VALUE *argv, VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval;
	int n1, n2, mode;
	IntGroupObject *psobj;
	IntGroup *pset;
	id theData;
	short *shortp;
	VALUE *nvalp;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pset = IntGroupFromValue(self);
	n2 = IntGroupGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[IntGroupObject alloc] initWithMDPointSet: pset] autorelease];
	mode = MyDocumentModifyAdd;
	if (argc >= 1) {
		nval = argv[0];
		if (rb_obj_is_kind_of(nval, rb_cString)) {
			if (argc == 1)
				rb_raise(rb_eStandardError, "Modify operation requires a single numeric argument");
			n1 = RSTRING_PTR(nval)[0];
			if (n1 == '=')
				mode = MyDocumentModifySet;
			else if (n1 == '*')
				mode = MyDocumentModifyMultiply;
			else if (n1 != '+')
				rb_raise(rb_eStandardError, "Modify operation should be either '=', '+' or '*'");
			nval = argv[1];
			if (mode != MyDocumentModifySet && !rb_obj_is_kind_of(nval, rb_cNumeric))
				rb_raise(rb_eStandardError, "Add or multiply operation requires a single numeric argument");
		}
	} else nval = Qnil;
	if (nval == Qnil) {
		VALUE pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
		MDPointer *pt = MDPointerFromMRPointerValue(pval);
		int idx = -1;
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
		if (mode == MyDocumentModifyMultiply)
			theData = [NSNumber numberWithFloat: (float)NUM2DBL(rb_Float(nval))];
		else
			theData = [NSNumber numberWithInt: NUM2INT(rb_Integer(nval))];
		[MyDocument modifyCodes: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: mode];
		return self;
	} else {
		int i;
		nval = rb_ary_to_ary(nval);
		n1 = (int)RARRAY_LEN(nval);
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
	int i, n1, n2, n3, mode;
	IntGroupObject *psobj;
	IntGroup *pset;
	id theData;
	float *floatp;
	VALUE *nvalp;
	MDPointer *pt;
	MDEvent *ep;
	int idx;

	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pset = IntGroupFromValue(self);
	n2 = IntGroupGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[IntGroupObject alloc] initWithMDPointSet: pset] autorelease];
	mode = MyDocumentModifyAdd;
	if (argc >= 1) {
		nval = argv[0];
		if (rb_obj_is_kind_of(nval, rb_cString)) {
			if (argc == 1)
				rb_raise(rb_eStandardError, "Modify operation requires a single numeric argument");
			n1 = RSTRING_PTR(nval)[0];
			if (n1 == '=')
				mode = MyDocumentModifySet;
			else if (n1 == '*')
				mode = MyDocumentModifyMultiply;
			else if (n1 != '+')
				rb_raise(rb_eStandardError, "Modify operation should be either '=', '+' or '*'");
			nval = argv[1];
			if (mode != MyDocumentModifySet && !rb_obj_is_kind_of(nval, rb_cNumeric))
				rb_raise(rb_eStandardError, "Add or multiply operation requires a single numeric argument");
		}
	} else nval = Qnil;
	
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
				rb_raise(rb_eStandardError, "event at %d is of different kind (%s) from the first event (%s)", (int)MDPointerGetPosition(pt), name1, name2);
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
		n1 = (int)RARRAY_LEN(nval);
		nvalp = RARRAY_PTR(nval);
		if ((kind == kMDEventTimeSignature && n1 >= 2 && rb_obj_is_kind_of(nvalp[0], rb_cNumeric))
			|| (kind == kMDEventSMPTE && n1 == 5 && rb_obj_is_kind_of(nvalp[0], rb_cNumeric))
			|| (kind == kMDEventKey && n1 >= 2 && rb_obj_is_kind_of(nvalp[0], rb_cString) && rb_obj_is_kind_of(nvalp[1], rb_cNumeric)))
			n3 = 1;
		else n3 = 2; /* array */
	} else {
		nval = rb_ary_to_ary(nval);
		n1 = (int)RARRAY_LEN(nval);
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
			floatp[i] = (float)NUM2DBL(rb_Float(rb_yield(pval)));
			i++;
		}
		[MyDocument modifyData: theData forEventKind: kind ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: MyDocumentModifySet];
		return self;
	} else if (n3 == 1) {
		theData = [NSNumber numberWithFloat: (float)NUM2DBL(rb_Float(nval))];
		[MyDocument modifyData: theData forEventKind: kind ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: mode];
		return self;
	} else {
		theData = [NSMutableData dataWithLength: sizeof(float) * n2];
		floatp = (float *)[theData mutableBytes];
		for (i = 0; i < n1 && i < n2; n1++) {
			floatp[i] = (float)NUM2DBL(rb_Float(nvalp[i]));
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
 *     MREventSet.modify_data(op, num)  #  op is either "=", "+", or "*"
 *     MREventSet.modify_data(num)      #  same as ("+", num)
 *     MREventSet.modify_data(array)
 *     MREventSet.modify_data { |pt| }
 *
 *  Modify the code of the specified events.
 *  In the first form, the data are set, shift, or multiplied by the argument.
 *  The second form is equivalent to modify_data("+", num) (i.e. shifted by the argument)
 *  In the third form, the new data values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the fourth form, the new data values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyData(int argc, VALUE *argv, VALUE self)
{
	return s_MREventSet_ModifyDataSub(argc, argv, self, -1);
}

/*
 *  call-seq:
 *     MREventSet.modify_velocity(op, num)  #  op is either "=", "+", or "*"
 *     MREventSet.modify_velocity(num)      #  same as ("+", num)
 *     MREventSet.modify_velocity(array)
 *     MREventSet.modify_velocity { |pt| }
 *
 *  Modify the velocities of the specified events. All specified events must be note events.
 *  In the first form, the velocities are set, shift, or multiplied by the argument.
 *  The second form is equivalent to modify_velocity("+", num) (i.e. shifted by the argument)
 *  In the third form, the new velocity values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the fourth form, the new velocity values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyVelocity(int argc, VALUE *argv, VALUE self)
{
	return s_MREventSet_ModifyDataSub(argc, argv, self, kMDEventNote);
}

/*
 *  call-seq:
 *     MREventSet.modify_release_velocity(op, num)  #  op is either "=", "+", or "*"
 *     MREventSet.modify_release_velocity(num)      #  same as ("+", num)
 *     MREventSet.modify_release_velocity(array)
 *     MREventSet.modify_release_velocity { |pt| }
 *
 *  Modify the release velocities of the specified events. All specified events must be note events.
 *  In the first form, the release velocities are set, shift, or multiplied by the argument.
 *  The second form is equivalent to modify_release_velocity("+", num) (i.e. shifted by the argument)
 *  In the third form, the new release velocity values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the fourth form, the new release velocity values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyReleaseVelocity(int argc, VALUE *argv, VALUE self)
{
	return s_MREventSet_ModifyDataSub(argc, argv, self, kMDEventInternalNoteOff);
}

/*
 *  call-seq:
 *     MREventSet.modify_duration(op, num)  #  op is either "=", "+", or "*"
 *     MREventSet.modify_duration(num)      #  same as ("+", num)
 *     MREventSet.modify_duration(array)
 *     MREventSet.modify_duration { |pt| }
 *
 *  Modify the duration of the specified events.
 *  In the first form, the durations are set, shift, or multiplied by the argument.
 *  The second form is equivalent to modify_duration("+", num) (i.e. shifted by the argument)
 *  In the third form, the new duration values are taken from the array.
 *  (If the number of objects in the array is less than the number of events in the given set,
 *  then the last value is repeated)
 *  In the fourth form, the new duration values are given by the block. The block arguments
 *  are the event pointer (note: the same pointer will be reused for every iteration).
 */
static VALUE
s_MREventSet_ModifyDuration(int argc, VALUE *argv, VALUE self)
{
	const MyDocumentTrackInfo *ip;
	VALUE tval, nval;
	int n1, n2, mode;
	IntGroupObject *psobj;
	IntGroup *pset;
	id theData;
	MDTickType *tickp;
	VALUE *nvalp;
	tval = rb_ivar_get(self, s_ID_track);
	if (tval == Qnil)
		rb_raise(rb_eStandardError, "Track is not given");
	ip = TrackInfoFromMRTrackValue(tval);
	pset = IntGroupFromValue(self);
	n2 = IntGroupGetCount(pset);
	if (n2 == 0)
		return self;
	psobj = [[[IntGroupObject alloc] initWithMDPointSet: pset] autorelease];
	mode = MyDocumentModifyAdd;
	if (argc >= 1) {
		nval = argv[0];
		if (rb_obj_is_kind_of(nval, rb_cString)) {
			if (argc == 1)
				rb_raise(rb_eStandardError, "Modify operation requires a single numeric argument");
			n1 = RSTRING_PTR(nval)[0];
			if (n1 == '=')
				mode = MyDocumentModifySet;
			else if (n1 == '*')
				mode = MyDocumentModifyMultiply;
			else if (n1 != '+')
				rb_raise(rb_eStandardError, "Modify operation should be either '=', '+' or '*'");
			nval = argv[1];
			if (mode != MyDocumentModifySet && !rb_obj_is_kind_of(nval, rb_cNumeric))
				rb_raise(rb_eStandardError, "Add or multiply operation requires a single numeric argument");
		}
	} else nval = Qnil;
	if (nval == Qnil) {
		VALUE pval = MRPointerValueFromTrackInfo(ip->track, ip->doc, ip->num, -1);
		MDPointer *pt = MDPointerFromMRPointerValue(pval);
		int idx = -1;
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
		if (mode == MyDocumentModifyMultiply)
			theData = [NSNumber numberWithFloat: (float)NUM2DBL(rb_Float(nval))];
		else
			theData = [NSNumber numberWithLong: (int32_t)(NUM2INT(rb_Integer(nval)))];
		[MyDocument modifyDurations: theData ofMultipleEventsAt: psobj forMDTrack: ip->track inDocument: ip->doc mode: mode];
		return self;
	} else {
		int i;
		nval = rb_ary_to_ary(nval);
		n1 = (int)RARRAY_LEN(nval);
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
	rb_cIntGroup = rb_define_class("PointSet", rb_cObject);
	rb_include_module(rb_cIntGroup, rb_mEnumerable);
	rb_define_alloc_func(rb_cIntGroup, MRPointSet_Alloc);
	rb_define_method(rb_cIntGroup, "clear", s_MRPointSet_Clear, 0);
	rb_define_method(rb_cIntGroup, "initialize", s_MRPointSet_Initialize, -1);
	rb_define_method(rb_cIntGroup, "initialize_copy", s_MRPointSet_InitializeCopy, 1);
	rb_define_method(rb_cIntGroup, "length", s_MRPointSet_Length, 0);
	rb_define_alias(rb_cIntGroup, "size", "length");
	rb_define_method(rb_cIntGroup, "member?", s_MRPointSet_MemberP, 1);
	rb_define_alias(rb_cIntGroup, "include?", "member?");
	rb_define_method(rb_cIntGroup, "each", s_MRPointSet_Each, 0);
	rb_define_method(rb_cIntGroup, "[]", s_MRPointSet_ElementAtIndex, 1);
	rb_define_method(rb_cIntGroup, "add", s_MRPointSet_Add, 1);
	rb_define_alias(rb_cIntGroup, "<<", "add");
	rb_define_method(rb_cIntGroup, "delete", s_MRPointSet_Delete, 1);
	rb_define_method(rb_cIntGroup, "reverse", s_MRPointSet_Reverse, 1);
	rb_define_method(rb_cIntGroup, "merge", s_MRPointSet_Add, 1);
	rb_define_method(rb_cIntGroup, "subtract", s_MRPointSet_Delete, 1);
	rb_define_method(rb_cIntGroup, "union", s_MRPointSet_Union, 1);
	rb_define_method(rb_cIntGroup, "difference", s_MRPointSet_Difference, 1);
	rb_define_method(rb_cIntGroup, "intersection", s_MRPointSet_Intersection, 1);
	rb_define_method(rb_cIntGroup, "sym_difference", s_MRPointSet_SymDifference, 1);
	rb_define_method(rb_cIntGroup, "convolute", s_MRPointSet_Convolute, 1);
	rb_define_method(rb_cIntGroup, "deconvolute", s_MRPointSet_Deconvolute, 1);
	rb_define_method(rb_cIntGroup, "offset", s_MRPointSet_Offset, 1);
	rb_define_alias(rb_cIntGroup, "+", "union");
	rb_define_alias(rb_cIntGroup, "|", "union");
	rb_define_alias(rb_cIntGroup, "-", "difference");
	rb_define_alias(rb_cIntGroup, "&", "intersection");
	rb_define_alias(rb_cIntGroup, "^", "sym_difference");
	rb_define_method(rb_cIntGroup, "range_at", s_MRPointSet_RangeAt, 1);
	rb_define_method(rb_cIntGroup, "inspect", s_MRPointSet_Inspect, 0);
	rb_define_alias(rb_cIntGroup, "to_s", "inspect");
	rb_define_singleton_method(rb_cIntGroup, "[]", s_MRPointSet_Create, -1);

	/*  Class MREventSet: it is an MREventSet with an associated Track  */
	rb_cMREventSet = rb_define_class("EventSet", rb_cIntGroup);
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
