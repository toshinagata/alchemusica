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

class Sequence

def change_control_number_ext
  hash = Dialog.run {
    layout(1,
	  layout(2,
	    item(:text, :title=>"Old control Number"),
	    item(:textfield, :width=>40, :range=>[0, 127], :tag=>"old"),
	    item(:text, :title=>"New control number"),
	    item(:textfield, :width=>40, :range=>[0, 127], :tag=>"new")),
	  item(:checkbox, :title=>"Change only editable tracks", :tag=>"editable_only"),
	  item(:checkbox, :title=>"Change only selected events", :tag=>"selection_only"))
  }
  if hash["status"] == 0
	old = hash["old"]
	new = hash["new"]
	editable_only = hash["editable_only"]
	selection_only = hash["selection_only"]
#	puts "old = #{old}, new = #{new}, editable_only = #{editable_only}"
	each_track { |tr|
	  next if editable_only && !tr.editable?
	  tr.send(selection_only ? :each_selected : :each) { |p|
		if p.kind == :control && p.code == old
		  p.code = new
		end
	  }
	}
  end
end

def change_timebase
  timebase = self.timebase
  hash = Dialog.run("Change Timebase") {
    layout(1,
	  layout(2,
	    item(:text, :title=>"Current timebase = #{timebase}"),
		nil,
	    item(:text, :title=>"New timebase"),
	    item(:textfield, :width=>40, :range=>[24, 960], :tag=>"new")))
  }
#    p hash
  if hash[:status] == 0
	new = hash["new"].to_f
	mult = new / timebase
	each_track { |tr|
	  set1 = tr.all_events
	  set2 = tr.eventset { |p| p.kind == :note }
	  set2.modify_duration("*", mult)
	  set1.modify_tick("*", mult)
	}
	self.set_timebase(new)
  end
end

def randomize_ticks
  wd = (get_global_settings("randomize_tick_width") || "10").to_f
  if !self.has_selection
    message_box("No events are selected.", "Error", :ok);
    return
  end
  hash = Dialog.run("Randomize Ticks") {
    layout(1,
	  layout(1,
	    item(:text, :title=>"Randomize width (in milliseconds, 10-1000)"),
	    item(:textfield, :width=>40, :value=>wd.to_s, :range=>[10, 1000], :tag=>"width")))
  }
  if hash[:status] == 0
    wd = hash["width"].to_f
	set_global_settings("randomize_tick_width", wd.to_s)
    each_track { |tr|
      s = tr.selection
  	  t = []
  	  s.each { |p|
	    t1 = self.tick_to_time(p.tick)
	    t2 = t1 + (rand() - 0.5) * wd / 1000.0
	    t.push(Integer(self.time_to_tick(t2)))
	  }
      s.modify_tick(t)
    }
  end
end

end

register_menu("Change timebase...", :change_timebase)
register_menu("Randomize ticks...", :randomize_ticks, 1)
# register_menu("Change control number...", :change_control_number_ext)
