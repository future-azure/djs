require '../../lib/djs'

class PegSolitaire < DJS::DJSConnection
  UNUSED_GRIDS = [
    '00', '01', '05', '06',
    '10', '11', '15', '16',
    '50', '51', '55', '56',
    '60', '61', '65', '66',
  ]
  MARU1 = "\u25cf"
  MARU2 = "\u25cb"
  @@conns = Hash.new

  def on_open
    grids = Hash.new
    pre = nil
    tds = Hash.new
    0.upto(6).each { |y|
      0.upto(6).each { |x|
        id = "#{y}#{x}"
        grids[id] = 0
        unless UNUSED_GRIDS.include? id
          grids[id] = 1
          ele = document.getElementById id
          ele.onmouseover = :on_mouse_over
          ele.onmouseout = :on_mouse_out
          ele.onclick = :on_click
          tds[id] = ele
        end
      }
    }
    grids['33'] = 0

    document.getElementById("status").innerHTML = ""
    document.getElementById("restart").onclick = :restart
    user_agent = navigator.userAgent.sync

    src_element = true
    if user_agent =~ /firefox/i
      src_element = false
    end

    @@conns[self.cid] = [grids, pre, tds, src_element]

    register_function :on_mouse_over
    register_function :on_mouse_out
  end

  def restart
    grids, pre, tds, src_element = @@conns[self.cid]

    grids = Hash.new
    pre = nil
    0.upto(6).each { |y|
      0.upto(6).each { |x|
        id = "#{y}#{x}"
        grids[id] = 0
        unless UNUSED_GRIDS.include? id
          grids[id] = 1
          tds[id].conn = self
          tds[id].innerHTML = MARU1
        end
      }
    }
    grids['33'] = 0
    tds['33'].innerHTML = ''

    @@conns[self.cid] = [grids, pre, tds, src_element]
  end

  def on_mouse_over(event)
    if @@conns[self.cid][3]
      ele = event.srcElement
    else
      ele = event.target
    end
    ele.style.border = 'solid 1px red'
    ele.style.cursor = 'hand'
  end

  def on_mouse_out(event)
    if @@conns[self.cid][3]
      ele = event.srcElement
    else
      ele = event.target
    end
    ele.style.border = 'solid 1px white'
    ele.style.cursor = 'pointer'
  end

  def on_click(event)
    grids, pre, tds, src_element = @@conns[self.cid]

    if src_element
      ele = event.srcElement
    else
      ele = event.target
    end

    id = ele.id.sync
    if grids[id] == 1
      unless pre
        ele.innerHTML = MARU2
        grids[id] = 2
        pre = id
      end
    elsif grids[id] == 2
      ele.innerHTML = MARU1
      grids[id] = 1
      pre = nil
    else
      if pre
        y1 = pre[0].to_i
        x1 = pre[1].to_i
        y2 = id[0].to_i
        x2 = id[1].to_i

        if y1 == y2 && (x1 - x2).abs == 2
          tds[pre].conn = self
          tds[pre].innerHTML = ''
          grids[pre] = 0
          key = "#{y1}#{x1 - (x1 - x2) / 2}"
          tds[key].conn = self
          tds[key].innerHTML = ''
          grids[key] = 0
          ele.innerHTML = MARU1
          grids[id] = 1
          pre = nil
        elsif x1 == x2 && (y1 - y2).abs == 2
          tds[pre].conn = self
          tds[pre].innerHTML = ''
          grids[pre] = 0
          key = "#{y1 - (y1 - y2) / 2}#{x1}"
          tds[key].conn = self
          tds[key].innerHTML = ''
          grids[key] = 0
          ele.innerHTML = MARU1
          grids[id] = 1
          pre = nil
        end
      end
    end

    @@conns[self.cid] = [grids, pre, tds, src_element]
  end

  def on_error(error)
    p '***********************************************************'
    p error
    p '***********************************************************'
  end
end