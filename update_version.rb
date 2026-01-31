#!/usr/bin/ruby

require 'kconv'

#  Get the version string
#  version = "X.X.X"
#  date = "yyyymmdd"
version = nil
date = nil
svn_revision = nil
eval IO.read("Version")
eval IO.read("lastBuild.txt")
ver = version
t = Time.now
year = t.year
month = t.month
day = t.day
d = sprintf("%04d%02d%02d", year, month, day)
# if date != d
#   File.open("Version", "w") { |fp|
#     fp.print "version = \"#{version}\"\n"
#     fp.print "date = \"#{d}\"\n"
#   }
# end
build = "build " + d
verstr = "v#{ver} #{build}"
yrange = "2000-#{year}"

def modify_file(name, enc = nil, &block)
  return if name =~ /~$/
  enc ||= 'utf-8'
  modified = false
  ary = []
  fp = open(name, "rb", :encoding => enc)
  if fp
    ary = fp.read.encode("utf-8").split("\n")
    ary.each_with_index { |s, i|
      s = block.call(s)
      if s
        modified = true if ary[i] != s
        ary[i] = s
      end
    }
    fp.close
  end
  if modified
    fp = open(name, "wb", :encoding => enc)
    if fp
      s = ary.join("\n") + "\n"
      fp.write(s.encode(enc))
      fp.close
    end
  end
end

#  Modify Info.plist
["Alchemusica-Info.plist", "Alchemusica-Legacy-info.plist"].each { |nm|
  version = false
  modify_file(nm) { |s|
    if version
      version = false
      "\t<string>#{ver}</string>\n"
    else
      version = (s =~ /\bCFBundleVersion\b/)
      nil
    end
  }
}

#  Modify InfoPlist.strings
Dir["*.lproj/InfoPlist.strings"].each { |nm|
  modify_file(nm, 'utf-16') { |s|
    olds = s.dup
    s.sub!(/Copyright [-0-9]+/, "Copyright #{yrange}")
    s.sub!(/Version [.0-9a-z]+( +\(rev [0-9]+\))?/, "Version #{ver} (rev #{svn_revision})")
    if olds != s
      s
    else
      nil
    end
  }
}

#  Modify all source files (but only the last modified year does not match year range)
sources = Dir["Classes/*"] + Dir["MD_package/*"] + Dir["Ruby_bindings/*"] + Dir["Ruby_Scripts/*"] + ["main.m"]
sources.each { |nm|
  mtime = File::mtime(nm)
  y = mtime.year.to_s
  modify_file(nm) { |s|
    news = nil
    if s =~ /Copyright\s+(\([cC]\)\s+)?([-0-9]+)/
      s0 = $~.pre_match
      s1 = $~.post_match
      cmark = $1
      years = $2
      y1, y2 = years.split(/-/)
      y2 ||= y1
      if y != y2
        years = "#{y1}-#{y}"
        news = s0 + "Copyright #{cmark}#{years}" + s1
      end
    end
    news
  }
}

#  Modify doc_source.html
if false
modify_file("Documents/src/doc_source.html") { |s|
  if s =~ /Version/ && s.sub!(/[Vv][-.0-9 A-Za-z_]*/, "Version #{ver} #{build}")
    s
  else
    nil
  end
}
end

#  Modify README
if false
modify_file("README") { |s|
  if s =~ /        Version/ && s.sub!(/[Vv][-.0-9 A-Za-z_]*/, "Version #{ver} #{build}")
    s
  else
    nil
  end
}
end
