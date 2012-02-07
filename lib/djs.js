var WS;
var REFS;
var SERVER;
var CALLBACKS;
var handshaked;
var isWebsocket;
var TASKS;
var EVENTS;
var FUNCS;

// WebSocket Implementation
function djs_start_websocket(server) {
    WS = new WebSocket(server);
    WS.onopen = on_open;
    WS.onclose = on_close;
    WS.onmessage = on_message;
    WS.onerror = on_error;
    handshaked = false;
    REFS = new Array();
    TASKS = new Array();
    CALLBACKS = new Array();
    isWebsocket = true;
    EVENTS = new Array();
    FUNCS = new Array();
}

function websocket_handshake() {
    WS.send("0\t0\t");
}

function on_open() {
    websocket_handshake();
    console.log("opened");
}

function on_close() {
    console.log("closed");
}

function on_message(event) {
    if (!handshaked) {
        handshaked = true;
        DJS_ID = event.data;
        WS.send("1\t" + DJS_ID + "\t");
    } else {
        if (event.data == "\t") {
            return;
        }
        var rsp = djs_eval(event.data);
        WS.send("2\t" + DJS_ID + "\t" + rsp);
    }
}

function on_error(error) {
    console.log("error");
}

function oncallback(cid, method, event) {
    WS.send("5\t" + cid + "\t" + method);
}

// AJAX Implementation
function djs_start_ajax(server) {
    SERVER = server;
    REFS = new Array();
    TASKS = new Array();
    CALLBACKS = new Array();
    isWebsocket = false;
    EVENTS = new Array();
    FUNCS = new Array();

    handshake();
}

function djs_send(msg, callback) {
    message(msg, callback);
}

function getXmlHttpRequestObject() {
    var xhr;
    if (XMLHttpRequest) {
        xhr = new XMLHttpRequest();
    } else {
        try {
            xhr = new ActiveXObject('MSXML2.XMLHTTP.6.0');
        } catch (e) {
            try {
                xhr = new ActiveXObject('MSXML2.XMLHTTP.3.0');
            } catch (e) {
                try {
                    xhr = new ActiveXObject('MSXML2.XMLHTTP');
                } catch (e) {
                    xhr = null;
                    alert("This browser does not support XMLHttpRequest.");
                }
            }
        }
    }

    return xhr;
}

function handshake() {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            if (xhr.responseText == "\t") {
                return;
            }
            connect(xhr.responseText);
        }
    };
    xhr.send("0\t0\t");
}

function connect(id) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\t") {
                return;
            }
            if (rsp == "") {
                reconnect(id);
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    };
    xhr.send("1\t" + id + "\t");
}

function reconnect(id) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\t") {
                return;
            }
            if (rsp == "") {
                reconnect(id);
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    };
    xhr.send("6\t" + id + "\t");
}

function response(id, rsp) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\t") {
                return;
            }
            if (rsp == "") {
                reconnect(id);
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    };
    xhr.send("2\t" + id + "\t" + rsp);
}

function callback(cid, method, event) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            var id = rsp.substring(0, rsp.indexOf("\t"));
            if (rsp == "\t") {
                return;
            }
            var req = djs_eval(rsp.substring(rsp.indexOf("\t") + 1));
            response(id, req);
        }
    }
    var event_id = EVENTS.length;
    EVENTS[event_id] = event;
    xhr.send("5\t" + cid + "\t" + method + "\t" + event_id);
}

function rpc(id) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\t") {
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    }
    xhr.send("7\t" + id + "\t");
}

function djs_eval(json, ext) {
    var rsp = "";
    try {
        var reqs = json.split("\t");
        var info;
        var id;
        var cid;
        var obj;
        var content;
        var args;
        var result;
        var i;
        var ex;
        if (reqs[0] == "1") {
            for (i = 1; i < reqs.length; i++) {
                info = eval("(" + reqs[i] + ")");
                REFS[info.id].origin = info.origin;
            }
        } else if (reqs[0] == "2") {
            var func = json.substring(2, json.length);
            var nn = func.split(",", 1)[0];
            var cc = func.substring(nn.length + 1);
            createFunction(nn, cc);
            return;
        } else {
            for (i = 1; i < reqs.length; i++) {
                TASKS.push(reqs[i]);
            }
        }

        var req;
        rsp = "{";
        while (TASKS.length > 0) {
            req = TASKS.shift();
            info = eval("(" + req + ")");
            id = info.id;
            cid = info.cid;
            obj = info.type;
            content = info.content;
            args = info.args;
            ex = info.ex;

            if (obj == "rpc") {
                rpc(content);
                continue;
            }

            if (obj == "new") {
                var instance = "new " + content + "(";
                if (args && args.length > 0) {
                    instance += "args[0]";
                    for (i = 1; i < args.length; i++) {
                        instance += ",args[" + i + "]";
                    }
                }
                instance += ")";
                createRefObj(id, eval(instance));
                continue;
            }

            if (content.indexOf("{}") == 0) {
                obj[content.substring(2)] = createCallback(cid, info.args[0]);
                result = null;
            } else if (content == "[]") {
                // TODO args
                obj = to_ruby_object(id, obj[args[0]]);
                if (obj) {
                    rsp += id + "=>" + obj + ",";
                }
            } else if (content == "[]=") {
                obj[args[0]] = args[1];
            } else {
                if (!ext && isPrimitive(obj) && !obj[content]) {
                    to_ruby_object(info.id, null);
                    info.type = obj;
                    return toRubyHash(info);
                }

                if (args && args.length > 0) {
                    if (content.match(/^.+=$/)) {
                        var prop = content.substring(0, content.length - 1);
                        obj[prop] = args[0];
                        result = null;
                    } else {
                        if (!obj[content]) {
                            throw new Error("undefined method: '" + content + "'");
                        }
                        result = obj[content].apply(obj, args);
                    }
                } else {
                    result = obj[content];
                    if (result == undefined) {
                        throw new Error("undefine method or property: '" + content + "'");
                    }
                    if (result && typeof result == "function" && !(ex == "object")) {
                        result = result.call(obj);
                    }
                }
            }

            if (ext) {
                createRefObj(id, result);
            } else {
                obj = to_ruby_object(id, result);
                if (obj) {
                    rsp += id + "=>" + obj + ",";
                }
            }
        }

        if (rsp.length > 1) {
            rsp = rsp.substring(0, rsp.length - 1) + "}";
        } else {
            rsp += "}";
        }
    } catch (e) {
        rsp = "{'error'=>" + to_ruby_object(-1, e.message) + ",'id'=>" + id + "}";
    }
    return rsp;
}

function createRefObj(id, obj) {
    var refObj = new RefObj(id, obj);
    REFS[id] = refObj;
    return refObj;
}

function createCallback(cid, method) {
    return function(cid, method) {
        return function(e) {
            if (FUNCS[method]) {
                FUNCS[method](e);
            } else {
                if (isWebsocket) {
                    oncallback(cid, method, e);
                } else {
                    callback(cid, method, e);
                }
            }
        }
    }(cid, method);
}

function createFunction(name, content) {
    FUNCS[name] = function() {
        djs_eval(content, arguments);
    }
}

function RefObj(id, obj) {
    this.id = id;
    this.origin = obj;
}

function to_ruby_object(id, obj) {
    if (obj == undefined || obj == null) {
        return null;
    }

    var type = typeof obj;
    if (type == "string") {
        return "'" + obj.replace(/'/g, "\\'") + "'";
    } else if (type == "number" || type == "boolean") {
        return obj;
    } else {
        createRefObj(id, obj);
        return null;
    }
}

function isPrimitive(obj) {
    var type = typeof obj;
    return type == "string" || type == "number" || type == "boolean";
}

function toRubyHash(hash) {
    var ret = '{';
    for (key in hash) {
        ret += '"' + key + '"=>';
        if (typeof hash[key] == "string") {
            ret += '"' + hash[key] + '",';
        } else {
            if (hash[key] instanceof Array && hash[key].length == 0) {
                ret += '[],';
            } else {
                ret += hash[key] + ',';
            }
        }
    }
    if (ret.length > 1) {
        ret = ret.substring(0, ret.length - 1);
    }
    ret += '}';
    return ret;
}
