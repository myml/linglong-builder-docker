FROM registry.cn-hangzhou.aliyuncs.com/linyaps/builder:1.10.3_amd64
USER root
RUN apt-get update -y
RUN apt-get install -y openjdk-21-jre
ADD https://jenkins.linyaps.org.cn/jnlpJars/agent.jar /
RUN chmod 444 /agent.jar
USER builder