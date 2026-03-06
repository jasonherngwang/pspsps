enum ASRError: Error {
    case modelNotLoaded
    case engineUnavailable(String)
    case transcriptionFailed(String)
}
