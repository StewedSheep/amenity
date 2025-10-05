// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/amenity"
import topbar from "../vendor/topbar"
import Chart from "chart.js/auto"

// Custom hooks
const Hooks = {}

Hooks.CaptureSelection = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      
      const selectedText = window.getSelection().toString().trim()
      
      // Push event to the LiveView component with selected text
      this.pushEventTo(this.el.getAttribute("phx-target"), "show_form", {
        "selected-text": selectedText
      })
    })
  }
}

Hooks.AccuracyPieChart = {
  mounted() {
    const correctAnswers = parseInt(this.el.dataset.correct)
    const incorrectAnswers = parseInt(this.el.dataset.incorrect)
    
    // Only render if there's data
    if (correctAnswers === 0 && incorrectAnswers === 0) {
      this.el.innerHTML = '<div class="text-center text-gray-500 py-8">No trivia games played yet. Start playing to see your stats!</div>'
      return
    }

    const ctx = this.el.getContext('2d')
    
    this.chart = new Chart(ctx, {
      type: 'pie',
      data: {
        labels: ['Correct Answers', 'Incorrect Answers'],
        datasets: [{
          data: [correctAnswers, incorrectAnswers],
          backgroundColor: [
            'rgba(34, 197, 94, 0.8)',  // Green for correct
            'rgba(239, 68, 68, 0.8)'   // Red for incorrect
          ],
          borderColor: [
            'rgba(34, 197, 94, 1)',
            'rgba(239, 68, 68, 1)'
          ],
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              font: {
                size: 14,
                weight: 'bold'
              },
              padding: 20
            }
          },
          tooltip: {
            enabled: true,
            backgroundColor: 'rgba(0, 0, 0, 0.8)',
            titleFont: {
              size: 16,
              weight: 'bold'
            },
            bodyFont: {
              size: 14
            },
            padding: 12,
            callbacks: {
              label: function(context) {
                const label = context.label || ''
                const value = context.parsed || 0
                const total = correctAnswers + incorrectAnswers
                const percentage = ((value / total) * 100).toFixed(1)
                return `${label}: ${value} (${percentage}%)`
              }
            }
          }
        }
      }
    })
  },
  
  updated() {
    const correctAnswers = parseInt(this.el.dataset.correct)
    const incorrectAnswers = parseInt(this.el.dataset.incorrect)
    
    if (this.chart) {
      this.chart.data.datasets[0].data = [correctAnswers, incorrectAnswers]
      this.chart.update()
    }
  },
  
  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

