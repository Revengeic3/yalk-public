

export function DragElement(elmnt) {
    var pos1 = 0, pos2 = 0, pos3 = 0, pos4 = 0;
    if (document.getElementById("debug-header")) {
      /* if present, the header is where you move the DIV from:*/
      document.getElementById("debug-header").onmousedown = dragMouseDown;
    } else {
      /* otherwise, move the DIV from anywhere inside the DIV:*/
      elmnt.onmousedown = dragMouseDown;
    }
  
    // This is literally a copy/paste of fucking W3School and must be re-done
    function dragMouseDown(e) {
      e = e || window.event;
      e.preventDefault();
      // get the mouse cursor position at startup:
      pos3 = e.clientX;
      pos4 = e.clientY;
      document.onmouseup = closeDragElement;
      // call a function whenever the cursor moves:
      document.onmousemove = elementDrag;
    }
  
    function elementDrag(e) {
      e = e || window.event;
      e.preventDefault();
      // calculate the new cursor position:
      pos1 = pos3 - e.clientX;
      pos2 = pos4 - e.clientY;
      pos3 = e.clientX;
      pos4 = e.clientY;
      // set the element's new position:
      elmnt.style.top = (elmnt.offsetTop - pos2) + "px";
      elmnt.style.left = (elmnt.offsetLeft - pos1) + "px";
    }
  
    function closeDragElement() {
      /* stop moving when mouse button is released:*/
      document.onmouseup = null;
      document.onmousemove = null;
    }
  }

export function DebugBox() {
  let debugBox = new DocumentFragment()

  let debugWindow = document.createElement('div')
  let debugHeader = document.createElement('div')
  let debugContent = document.createElement('div')

  let debugPing = document.createElement('span')


  debugWindow.id = 'debug-window'
  debugHeader.id = 'debug-header'
  debugContent.id = 'debug-content'

  debugHeader.innerText = 'Debug'
  debugContent.innerText = 'Ping to server: '
  debugPing.id = 'ping'
  debugPing.className = 'debug-value'
  debugPing.innerText = '0ms'


  debugContent.appendChild(debugPing)

  debugWindow.appendChild(debugHeader)
  debugWindow.appendChild(debugContent)

  return debugBox.appendChild(debugWindow)
}