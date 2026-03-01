import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    vus: __ENV.CLIENTS ? parseInt(__ENV.CLIENTS) : 1, // 通过环境变量自定义client数
    iterations: (__ENV.CLIENTS ? parseInt(__ENV.CLIENTS) : 1) * 100, // 每个client 100次
    noConnectionReuse: false,
};

export default function () {
    let res = http.get('http://localhost:8080/foo');
    sleep(0.001);
}