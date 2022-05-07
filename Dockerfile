FROM mcr.microsoft.com/dotnet/sdk:6.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y curl file git libncurses5 libpython2.7 make pciutils python2.7 xz-utils zip && \
    apt-get clean

SHELL ["/bin/bash", "-c"]

# Only non-root users can install Tizen Studio.
RUN useradd -ms /bin/bash user
USER user
WORKDIR /home/user

# Install Tizen Studio.
ENV TIZEN_SDK=/home/user/tizen-studio
RUN curl -o installer.bin http://download.tizen.org/sdk/Installer/tizen-studio_4.6/web-cli_Tizen_Studio_4.6_ubuntu-64.bin && \
    chmod a+x installer.bin && \
    ./installer.bin --accept-license ${TIZEN_SDK} && \
    rm installer.bin
ENV PATH=${TIZEN_SDK}/tools/ide/bin:${TIZEN_SDK}/package-manager:${PATH}

# Install packages.
# RUN package-manager-cli.bin install NativeToolchain-Gcc-9.2 WEARABLE-4.0-NativeAppDevelopment-CLI

# Create a certificate profile.
RUN tizen certificate -a tizen -p tizen -f tizen && \
    tizen security-profiles add -n tizen -a ${TIZEN_SDK}-data/keystore/author/tizen.p12 -p tizen

# Install flutter-tizen.
RUN git clone https://github.com/flutter-tizen/flutter-tizen.git
ENV PATH=/home/user/flutter-tizen/bin:${PATH}
