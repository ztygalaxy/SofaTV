import Foundation
@main struct PlaybackRaceChecks {
    static func main() {
        var race = PlaybackRace(); let old = race.token
        precondition(race.webReady(old)); precondition(race.output == .web)
        precondition(race.nativeReady(old)); precondition(race.output == .native)
        precondition(!race.webReady(old))
        race.begin(); let current = race.token
        precondition(!race.nativeReady(old)); precondition(!race.webReady(old)); precondition(race.output == .loading)
        precondition(race.nativeReady(current)); precondition(!race.webReady(current))
        race.begin(); race.failNative(race.token); precondition(race.webReady(race.token)); precondition(race.output == .web)
        race.begin(); race.failWeb(race.token); race.failNative(race.token); precondition(race.output == .failed)
        print("Playback race: web-first, native-first, handoff, stale callbacks and failures passed")
    }
}
