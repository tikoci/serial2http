FROM python:3.11-alpine
WORKDIR /app
RUN pip install --no-cache-dir 'pyserial>=3.5' 
COPY serial2http.py /app/bin
CMD [ "python", "/app/bin/serial2http.py" ]
