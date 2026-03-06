enum PostProcessError: Error {
    case engineUnavailable(String)
    case postProcessingFailed(String)
}
