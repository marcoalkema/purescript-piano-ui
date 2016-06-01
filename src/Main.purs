module Main where

import App.Routes (match)
import App.Layout (Action(PageView), State, view, update)
import Control.Monad.Eff
import DOM.Timer
import Control.Monad.Eff.Class 
import DOM (DOM)
-- import Prelude (bind, return, (++), show, not, unit, ($), (<$>), (<<<), map, (<>), (==), pure, (>))
import Prelude
import Pux
import Pux.Router (sampleUrl)
import Signal ((~>))
import Signal.Channel
import Control.Monad.Eff.Exception
import Control.Monad.Eff.Console
import Prelude (Unit, (>>=), const, bind)
import VexFlow (VEXFLOW, createCanvas)
import MidiPlayer
import MidiToVexFlow (renderMidi)
import HeartBeat
import Data.Foldable
import NoteHelper
import VexFlow
import Signal
import ClearCanvas
import Data.List
import Data.Function
import App.UI as UI
import Pux.Html (Html)
import App.Layout
import Control.Monad.Aff
import Data.Maybe
import Data.Either
import MidiToVexFlow
import Quantizer
import Data.Tuple
import Data.Foreign
import ColorNotation

type AppEffects = (dom :: DOM)
type MidiNote = Int

-- Entry point for the browser.
-- main :: forall e. State -> Eff (heartbeat :: HEARTBEAT, console :: CONSOLE, dom :: DOM, channel :: CHANNEL, err :: EXCEPTION, vexFlow :: VEXFLOW, midi :: MidiPlayer.MIDI, canvas :: ClearCanvas.CANVAS | e) (App State Action)
main state = do
  midiDataChannels <- loadMidi
  let midiDataSubscription :: Signal (Array Foreign)
      midiDataSubscription = subscribe midiDataChannels.midi
      ticksSubscription :: Signal Number
      ticksSubscription = subscribe midiDataChannels.ticks
      ticksSignal :: Signal Action
      ticksSignal = ticksSubscription ~> setTicks
      processedMidiSignal  :: Signal Action
      processedMidiSignal  = midiDataSubscription ~> \x -> setMidiData <<< getMidiNotes $  (processMidi x).midiNotes
      midiEventSignal  :: Signal Action
      midiEventSignal  = midiDataSubscription ~> setMidiEvent

  urlSignal <- sampleUrl
  let routeSignal :: Signal Action
      routeSignal = urlSignal ~> \r -> PageView (match r)

  playBackChannel <- playBackNoteSignal
  let trackSubscription :: Signal MidiNote
      trackSubscription       = subscribe playBackChannel
      incrementPlayBackSignal = trackSubscription ~> incrementPlayIndex 
      playBackSignal          = trackSubscription ~> setCurrentPlayBackNote
  runSignal (trackSubscription ~> \x -> MidiPlayer.logger x)

  userChannel <- userNoteSignal
  let userInputSubscription :: Signal MidiNote
      userInputSubscription = subscribe userChannel
      userInputSignal       = userInputSubscription ~> setCurrentKeyBoardInput 
      triggerSignal         = userInputSubscription ~> \midiNote -> setUserMelody
  runSignal (userInputSubscription ~> \midiNote -> MidiPlayer.logger midiNote)
  
  app <- start
    { initialState: state
    , update:
      fromSimple update
    , view: view
    , inputs: [fromJust $ mergeMany [routeSignal, playBackSignal, incrementPlayBackSignal, userInputSignal, triggerSignal, processedMidiSignal, midiEventSignal, ticksSignal ]]
    }

  renderToDOM "#app" app.html

  runSignal (app.state ~> \state -> drawNoteHelper state.ui.currentPlayBackNote state.ui.currentMidiKeyboardInput )
  loadHeartBeat midiFile (send playBackChannel) (send userChannel)
  runSignal (app.state ~> \state -> draw state.ui.currentPlayBackNoteIndex state.ui.midiEvents)
  
  return app

draw i midi = do
  clearCanvas "notationCanvas"
  canvas <- createCanvas "notationCanvas"
  renderMidi canvas i midi
  return unit

loadMidi = do
  chan <- channel []
  let mail = send chan
  chan2 <- channel 0.0
  let mail2 = send chan2
  let midiChannels = { midi  : chan
                     , ticks : chan2 }
  MidiPlayer.loadFile midiFile
  MidiPlayer.loadPlugin { soundfontUrl : "midi/examples/soundfont/"
                        , instrument   : "acoustic_grand_piano" }
    (const $ MidiPlayer.getData2 mail mail2)
  return midiChannels

-- processForeign d = do
--   ticksPerBeat <- getTicksPerBeat
  
  


-- playBackNoteSignal :: forall e. Eff (heartbeat :: HEARTBEAT, channel :: CHANNEL | e) (Channel MidiNote)
playBackNoteSignal = do 
  chan <- channel 0
  let mail = send chan
  return chan

-- userNoteSignal :: forall e. Eff (heartbeat :: HEARTBEAT, channel :: CHANNEL | e) (Channel MidiNote)
userNoteSignal = do 
  chan <- channel 0
  let mail = send chan
  return chan

midiDataSignal :: forall e. Eff (midi :: MidiPlayer.MIDI, channel :: CHANNEL | e)
 (Channel (Array Foreign))
midiDataSignal = do
  chan <- channel []
  return chan

midiFile = "colorTest4.mid"

drawNoteHelper playBackNote userNote = do
  clearRect "noteHelperCanvas"
  noteHelperCanvas   <- createCanvas "noteHelperCanvas"
  noteHelperRenderer <- createRenderer noteHelperCanvas 
  noteHelper         <- drawHelperStaff noteHelperRenderer playBackNote userNote
  return unit

type MidiNotes = { midiNotes :: Array MidiJsTypes.MidiNote }

getMidiNotes xs = map (_.noteNumber) xs

processMidi :: Array Foreign -> MidiNotes
processMidi midiData = do
  let safeData  :: List MidiJsTypes.MidiEvent
      safeData  = toList $ map unsafeF1 midiData
      midiNotes :: Array MidiJsTypes.MidiNote
      midiNotes = toUnfoldable $ Data.List.filter (\x -> x.noteNumber > 0)
                  <<< map (quantizeNote 1000.0 0.0)
                  <<< calculateDuration
                  <<< map (\midiObject -> Tuple midiObject false) -- midiEventWriter
                  <<< Data.List.filter filterNotes
                  $ toList safeData
  { midiNotes }

setCurrentKeyBoardInput :: MidiNote -> App.Layout.Action
setCurrentKeyBoardInput n = Child (UI.SetMidiKeyBoardInput n)

incrementPlayIndex :: Int -> App.Layout.Action
incrementPlayIndex n = Child (UI.IncrementPlayBackIndex)

setCurrentPlayBackNote :: MidiNote -> App.Layout.Action
setCurrentPlayBackNote n = Child (UI.SetPlayBackNote n)

setUserMelody :: App.Layout.Action
setUserMelody = Child (UI.SetUserMelody)

setMidiData :: (Array MidiNote) -> App.Layout.Action
setMidiData m = Child (UI.SetMidiData m)

setTicks :: Number -> App.Layout.Action
setTicks n = Child (UI.SetTicks n)

setMidiEvent :: Array Foreign -> App.Layout.Action
setMidiEvent m = Child (UI.SetMidiEvent m)
