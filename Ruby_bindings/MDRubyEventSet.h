/*
 *  MDRubyEventSet.h
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 09/09/06.
 *  Copyright 2009-2016 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDRubyEventSet__
#define __MDRubyEventSet__

#include "MDHeaders.h"
#include <ruby.h>

extern VALUE rb_cIntGroup, rb_cMREventSet;

extern IntGroup *IntGroupFromValue(VALUE val);
extern VALUE ValueFromIntGroup(IntGroup *pset);

extern VALUE MREventSetValueFromIntGroupAndTrackInfo(IntGroup *pset, MDTrack *track, void *myDocument, int isEndOfTrackSelected);
extern VALUE MREventSet_Track(VALUE self);
extern VALUE MREventSet_EOTSelected(VALUE self);
extern VALUE MREventSet_SetTrack(VALUE self, VALUE val);
extern VALUE MREventSet_SetEOTSelected(VALUE self, VALUE val);

extern void MREventSetInitClass(void);

#endif /* __MDRubyEventSet__ */
