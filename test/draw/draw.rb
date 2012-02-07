require '../../lib/djs'

class LogoConnection < DJS::DJSConnection
  KEYWORDS = ['HOME', 'CL', 'CLEAR', 'CS', 'CLEAN', 'CG',\
      'PU', 'PENUP', 'PD', 'PENDOWN',\
      'FD', 'FORWARD', 'BK', 'BACKWARD',\
      'LT', 'LEFT', 'RT', 'RIGHT',\
      'REPEAT', 'TO', 'IF', 'STOP'
  ]
  BRACKET = {:round => ['(', ')'], :square => ['[', ']']}
  NUMBER_PATTERN = /[\d.]+/

  @@params = Hash.new

  def on_open
    @@params[cid] = [false, 90, 250.0, 250.0, true]
    document.getElementById("draw").disabled = false
    document.getElementById("draw").onclick = :draw
  end

  def draw
    document.getElementById("draw").disabled = true
    stopped, degree, x, y, pen = @@params[cid]
    @ctx = document.getElementById("canvas").getContext("2d")
    @ctx.beginPath
    @ctx.strokeStyle = "rgb(0, 0, 0)"
    @ctx.moveTo(x, y)
    command = document.getElementById("command").value.sync
    unless command.empty?
      @@params[cid] = parse(split(command), degree, x, y, pen)
    end
    @ctx.closePath
    document.getElementById("draw").disabled = false
  end

  def split(command)
    command.strip!
    command.upcase!
    command.gsub!(/([\[\]()+\-*\/%<>=&|])/, " \\1 ")
    command.split(/\s+/)
  end

  def parse(tokens, degree, x, y, pen)
    stop = false
    i = 0
    while i < tokens.length
      case tokens[i]
      when 'HOME'
        degree, x, y = 90, 250, 250
        @ctx.moveTo(x, y)
        i += 1
      when 'CL', 'CLEAR', 'CS', 'CLEAN', 'CG'
        @ctx.clearRect(0, 0, 500, 500)
        i += 1
      when 'PU', 'PENUP'
        pen = false
        i += 1
      when 'PD', 'PENDOWN'
        pen = true
        i += 1
      when 'FD', 'FORWARD'
        param, i = get_param(tokens, i + 1)
        x, y = to_point(degree, x, y, param)
        if pen
          @ctx.lineTo(x, y)
          @ctx.stroke
        else
          @ctx.moveTo(x, y)
        end
      when 'BK', 'BACKWARD'
        degree += 180
        param, i = get_param(tokens, i + 1)
        x, y = to_point(degree, x, y, param)
        degree -= 180
        if pen
          @ctx.lineTo(x, y)
          @ctx.stroke
        else
          @ctx.moveTo(x, y)
        end
      when 'LT', 'LEFT'
        param, i = get_param(tokens, i + 1)
        degree += param
        degree %= 360
      when 'RT', 'RIGHT'
        param, i = get_param(tokens, i + 1)
        degree -= param
        degree %= 360
      when 'REPEAT'
        count, i = get_param(tokens, i + 1)
        body, i = tokens_in_brackets(:square, tokens, i)
        count.to_i.times {
          stopped, degree, x, y, pen = parse(body, degree, x, y, pen)
          break if stopped
        }
      when 'TO'
        name = tokens[i += 1]
        if name !~ /[A-Z]+/ || KEYWORDS.include?(name)
          window.alert "Invalid procedure name \"#{name}\"."
          break
        end
        params = Hash.new
        while true
          case tokens[i += 1]
          when '['
            break
          when /:[A-Z]+/
            params[tokens[i]] = '@' + params.size.to_s
          else
            params = nil
            break
          end
        end
        break unless params
        body, i = tokens_in_brackets(:square, tokens, i)
        body.each_index { |idx|
          body[idx] = params[body[idx]] if params.key?(body[idx])
        }
        @@params[cid.to_s + name] = [params.size, body]
      when 'IF'
        param, i = get_param(tokens, i + 1)
        if tokens[i] != '['
          window.alert "Invalid IF statement."
          break
        end
        body, i = tokens_in_brackets(:square, tokens, i)
        if param
          stopped, degree, x, y, pen = parse(body, degree, x, y, pen)
          break if stopped
        end
      when 'STOP'
        stop = true
        break
      else
        if proc = @@params[cid.to_s + tokens[i]]
          params_size = proc[0]
          toks = copy(proc[1])
          if params_size > 0
            i += 1
            params_size.times { |n|
              param, i = get_param(tokens, i)
              toks.each_index { |idx|
                toks[idx] = param.to_s if toks[idx] == "@#{n}"
              }
            }
          else
            i += 1
          end
          stopped, degree, x, y, pen = parse(toks, degree, x, y, pen)
        else
          window.alert "Invalid command \"#{tokens[i]}\"."
          break
        end
      end
    end

    return stop, degree, x, y, pen
  end

  def get_param(tokens, i)
    body = []
    while i < tokens.size && tokens[i] =~ /[\d.]+|[+\-*\/%()><=&|]/
      break if body[-1] && body[-1] =~ /[\d.]+/ && tokens[i] =~ /[\d.]+|[(]/
      body << tokens[i]
      i += 1
    end
    return calculate(body), i
  end

  def calculate(tokens)
    return nil if tokens.empty?
    i = 0
    while i < tokens.size
      case tokens[i]
      when NUMBER_PATTERN
        result = tokens[i].to_f
        i += 1
      when '*', '/', '%'
        op = tokens[i]
        case tokens[i += 1]
        when NUMBER_PATTERN
          if result
            result = result.method(op).call tokens[i].to_f
            i += 1
          else
            break
          end
        when '('
          body, i = tokens_in_brackets(:round, tokens, i)
          tmp = calculate(body)
          if tmp && result
            result = result.method(op).call tmp
          else
            result = nil
          end
          break unless result
        else
          result = nil
          break
        end
      when '+', '-'
        tmp = calculate(tokens[i + 1, tokens.size])
        if tmp && result
          result = result.method(tokens[i]).call tmp
        else
          result = nil
        end
        break
      when '('
        body, i = tokens_in_brackets(:round, tokens, i)
        result = calculate(body)
        break unless result != nil
      when '>', '<', '='
        op = tokens[i]
        op = '==' if op == '='
        body = []
        while (i += 1) < tokens.size && tokens[i] !~ /[&|]/
          body << tokens[i]
        end
        tmp = calculate(body)
        if tmp != nil && result != nil
          result = result.method(op).call tmp
        else
          result = nil
          break
        end
      when '&', '|'
        op = tokens[i]
        tmp = calculate(tokens[i + 1, tokens.size])
        if tmp != nil && result != nil
          case op
          when '&'
            result = tmp && result
          when '|'
            result = tmp || result
          end
        else
          result = nil
        end
        break
      else
        result = nil
        break
      end
    end
    return result
  end

  def copy(tokens)
    toks = []
    tokens.each { |tok|
      toks << tok.dup
    }
    toks
  end

  def tokens_in_brackets(type, tokens, i)
    body = []
    bracket = 1
    while bracket > 0
      case tokens[i += 1]
      when BRACKET[type][0]
        bracket += 1
        body << tokens[i]
      when BRACKET[type][1]
        bracket -= 1
        body << tokens[i] if bracket > 0
      else
        body << tokens[i]
      end
    end
    return body, i + 1
  end

  def to_point(degree, x, y, distance)
    radian = Math::PI * degree / 180
    return (x + distance * Math.sin(radian)), (y + distance * Math.cos(radian))
  end
end
