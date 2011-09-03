/*
 *  MDRubyDocument.h
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/03/21.
 *  Copyright 2008-2011 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDRubySequence__
#define __MDRubySequence__

#include <ruby.h>

//  Sequence class
extern VALUE rb_cMRSequence;

@class MyDocument;

//  MyDocument <-> Sequence
MyDocument *MyDocumentFromMRSequenceValue(VALUE val);
VALUE MRSequenceFromMyDocument(MyDocument *doc);

VALUE MRSequence_Current(VALUE self);

VALUE MRSequence_GlobalSettings(VALUE self, VALUE key);
VALUE MRSequence_SetGlobalSettings(VALUE self, VALUE key, VALUE value);

void MRSequenceInitClass(void);

//  Execute a script in the context of "class Sequence ..."
int MDRubyLoadScriptUnderMRSequence(const char *fname);

//  Call a method of Sequence
void MDRubyCallMethodOfMRSequence(MyDocument *doc, const char *method, int argc, VALUE *argv);

#endif /* __MDRubySequence__ */
