require '../../lib/djs'

class ChatConnection < DJS::DJSConnection
  def receive_chat_msg(event)
    nickname = document.getElementById("nickname").value
    message_element = document.getElementById("message")
    message = message_element.value
    message_element.value = ""
    message_element.focus
    DJS.connections.send_chat_msg("#{escape(nickname.sync)}: #{escape(message.sync)}")
  end

  def send_chat_msg(message)
    msg_element = document.createElement("div")
    msg_element.innerHTML =
      "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
    chats = document.getElementById("chats")
    chats.insertBefore(msg_element, chats.firstChild)
  end

  def on_open
    document.getElementById("status").innerHTML = ""
    document.getElementById("btn").onclick = :receive_chat_msg
  end

  def on_error(error)
    p error
  end

  def escape(str)
    str.gsub!('&', '&amp;')
    str.gsub!('<', '&lt')
    str.gsub!('>', '&gt;')
    str
  end
end