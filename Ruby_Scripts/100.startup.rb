#    Copyright (c) 2010-2017 Toshi Nagata. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

#  This Ruby script is automatically invoked on startup

#  Do some initialization here

#  Convenience methods for MRDialog
#  These definitions allow MRDialog#run and MRDialog#new to accept a block,
#  which is executed under the context of the MRDialog object.
class Dialog

  def self.run(*args, &block)
    obj = Dialog.new(*args)
    obj.instance_eval(&block)
    obj.run
  end

  alias initialize_orig initialize

  def initialize(*args, &block)
    initialize_orig(*args)
	instance_eval(&block) if block
  end

  def value(tag)
    attr(tag, :value)
  end
  
  def set_value(tag, value)
    set_attr(tag, :value=>value)
	value
  end

end

class Sequence

  def has_selection
    each_track { |tr|
	  if tr.selection.length > 0
	    return true
	  end
	}
	return false
  end

end
