//
//  MDRubyTrack.h
//  Alchemusica
//
//  Created by Toshi Nagata on 08/03/27.
//  Copyright 2008-2011 Toshi Nagata. All rights reserved.
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDRubyTrack__
#define __MDRubyTrack__

#include "MDHeaders.h"
#include <ruby.h>

//  Track class
extern VALUE rb_cMRTrack;

MDTrack *MDTrackFromMRTrackValue(VALUE val);
struct MyDocumentTrackInfo *TrackInfoFromMRTrackValue(VALUE val);
VALUE MRTrackValueFromTrackInfo(MDTrack *track, void *doc, int num);

void MRTrackInitClass(void);

#endif /* __MDRubyTrack__ */
