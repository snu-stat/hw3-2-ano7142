# 1. 기반 이미지 설정
FROM rocker/tidyverse:4.4.0

# 2. 시스템 의존성 설치 (ImageMagick + IRkernel의 ZMQ 의존성)
USER root
RUN apt-get update && apt-get install -y \
    wget \
    git \
    imagemagick \
    libmagick++-dev \
    libzmq3-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Miniforge 설치
# (Miniconda 대신 Miniforge를 사용하는 이유:
#   - 기본 채널이 conda-forge로 고정되어 채널 충돌 없음
#   - libmamba 솔버가 기본 탑재되어 의존성 해결이 빠르고 메모리 사용량이 적음
#   기존 Miniconda + classic solver 조합은 jupyter+statsmodels+scipy를 한 번에
#   풀 때 빌드러너에서 시간/메모리 한계로 종료되는 사례가 잦음.)
ENV CONDA_DIR=/opt/conda
RUN wget --quiet https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O ~/miniforge.sh && \
    /bin/bash ~/miniforge.sh -b -p /opt/conda && \
    rm ~/miniforge.sh

# 4. Conda 경로 설정 및 환경 생성
ENV PATH=$CONDA_DIR/bin:$PATH
RUN conda config --set channel_priority strict && \
    conda config --set solver libmamba && \
    conda create -n r-reticulate -y \
        python=3.10 \
        numpy pandas matplotlib \
        scipy statsmodels patsy \
        notebook ipykernel nbformat
# 추가로 필요한 패키지 설치
# - scipy        : 비선형 최소제곱(curve_fit), 카이제곱 분포
# - statsmodels  : GLM (Binomial / Poisson / NegativeBinomial)
# - patsy        : statsmodels formula API에 필요
# - notebook/ipykernel/nbformat : Binder/주피터 노트북 변환·실행에 필요
#   ("jupyter" 메타패키지는 너무 무겁고 솔버 부담이 커서 핵심 구성요소만 명시)

# 5-1. R 패키지 설치 (reticulate, remotes, IRkernel)
#      - 패키지 설치 실패 시 빌드를 즉시 종료시키기 위해 requireNamespace 로 검증
RUN R -e "install.packages(c('reticulate', 'remotes', 'IRkernel'), repos='https://cloud.r-project.org')" && \
    R -e "stopifnot(all(sapply(c('reticulate','remotes','IRkernel'), requireNamespace, quietly=TRUE)))"

# 5-2. IRkernel 의 Jupyter kernelspec 등록
#      installspec() 은 내부적으로 'jupyter kernelspec install' 을 호출하므로
#      jupyter 실행 파일이 PATH 에서 검색되어야 한다.
#      jupyter 는 r-reticulate 환경에만 설치되어 있으므로 해당 env 의 bin 을
#      이 RUN 명령에 한해 PATH 앞쪽에 끼워준다.
RUN PATH="$CONDA_DIR/envs/r-reticulate/bin:$PATH" \
    R -e "IRkernel::installspec(user = FALSE)"

# 5-3. 본 과제 분석에 필요한 R 패키지 추가 설치
# - Lahman  : 메이저리그 Teams 데이터 (문제 2-1 ~ 2-4)
# - NHANES  : 흡연 예측 자료 (문제 1-1)
# - broom   : tidy() / augment() 출력 정리
# - MASS    : stepAIC, glm.nb (tidyverse 이미지에 포함되어 있으나 명시)
RUN R -e "install.packages(c('Lahman', 'NHANES', 'broom', 'MASS'), repos='https://cloud.r-project.org')"

# 6. reticulate가 사용할 Python 경로 고정 (환경 변수)
ENV RETICULATE_PYTHON=/opt/conda/envs/r-reticulate/bin/python

# 7. (선택) Binder 사용자를 위한 권한 설정
# Binder는 보통 'jovyan' 유저 권한으로 실행
RUN chown -R ${NB_USER:-root} /opt/conda

# 기본 실행 경로 설정
WORKDIR /home/rstudio
