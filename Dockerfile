FROM python:3.11-alpine
WORKDIR /app
RUN apk add py3-pyserial
# was: RUN pip install --no-cache-dir 'pyserial>=3.5' 
COPY serial2http.py /app
CMD [ "python", "/app/serial2http.py" ]
