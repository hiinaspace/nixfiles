# fenc and friends: ffmpeg-based anime encoding helpers.
# https://github.com/hiinaspace/animutools
{
  buildPythonApplication,
  hatchling,
  ffmpeg-python,
  more-itertools,
  tqdm,
  rich,
  guessit,
  langdetect,
  src,
}:

buildPythonApplication {
  pname = "animutools";
  version = "0.1.0-unstable";
  inherit src;
  pyproject = true;

  build-system = [ hatchling ];

  dependencies = [
    ffmpeg-python
    more-itertools
    tqdm
    rich
    guessit
    langdetect
  ];

  # Tests want a live ffmpeg/ffprobe and media fixtures; skip in the build sandbox.
  doCheck = false;

  meta = {
    description = "ffmpeg-based anime encoding helper (fenc)";
    homepage = "https://github.com/hiinaspace/animutools";
    mainProgram = "fenc";
  };
}
