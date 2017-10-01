//
//  MDRubyPointer.h
//  Alchemusica
//
//  Created by Toshi Nagata on 08/03/30.
//  Copyright 2008-2016 Toshi Nagata. All rights reserved.
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

#ifndef __MDRubyPointer__
#define __MDRubyPointer__

#include <ruby.h>
#include "MDHeaders.h"
#include "MyDocument.h"

@class MyDocument;

//  Pointer class
extern VALUE rb_cMRPointer;

//  Internal structure
typedef struct MRPointerInfo {
	MyDocumentTrackInfo trackInfo;  //  MDTrack is _not_ retained
	MDPointer *pointer;             //  MDPointer _is_ retained
} MRPointerInfo;

VALUE MREventSymbolFromEventKindAndCode(int kind, int code, int *is_generic);
int MREventKindAndCodeFromEventSymbol(VALUE sym, int *code, int *is_generic);

VALUE MRPointer_GetDataSub(const MDEvent *ep);
void MRPointer_SetDataSub(VALUE val, MDEvent *ep, MyDocument *doc, int trackNo, int32_t position);

MDPointer *MDPointerFromMRPointerValue(VALUE val);
VALUE MRPointerValueFromTrackInfo(MDTrack *track, MyDocument *doc, int num, int position);

VALUE MRPointer_Top(VALUE self);
VALUE MRPointer_Bottom(VALUE self);
VALUE MRPointer_Next(VALUE self);
VALUE MRPointer_Last(VALUE self);
VALUE MRPointer_NextInSelection(VALUE self);
VALUE MRPointer_LastInSelection(VALUE self);
// VALUE MRPointer_Flush(VALUE self);

void MRPointerInitClass(void);

#endif /* __MDRubyPointer__ */
