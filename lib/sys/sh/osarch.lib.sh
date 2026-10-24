
m_OSARCH_OS="$(command -p uname -s 2>/dev/null)" && m_OSARCH_ARCH="$(command -p uname -m 2>/dev/null)" || fatal system osarch-detection-failure

# normalize known operative systems, leave intact others
case "$m_OSARCH_OS" in
  Linux) m_OSARCH_OS="linux";;
  Darwin) m_OSARCH_OS="macos";;
  MINGW*|MSYS*|CYGWIN*) m_OSARCH_OS="windows";;
esac

# normalize known architectures, leave intact others
case "$m_OSARCH_ARCH" in
  arm64|aarch64|ARM64|AARCH64) m_OSARCH_ARCH="arm64";;
  x86_64|x64|amd64|AMD64|X86_64|X64) m_OSARCH_ARCH="x86_64";;
esac

# set platform
m_OSARCH="${m_OSARCH_OS}-${m_OSARCH_ARCH}"

export -- \
  m_OSARCH_OS \
  m_OSARCH_ARCH \
  m_OSARCH

readonly -- \
  m_OSARCH_OS \
  m_OSARCH_ARCH \
  m_OSARCH
